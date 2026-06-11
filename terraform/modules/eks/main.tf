# EKS cluster + the IAM/SQS scaffolding Karpenter needs.
#
# Bootstrap model (architecture/03-compute-platform.md): the cluster starts with
# NO managed node group. CoreDNS and the Karpenter controller run on AWS Fargate
# (kube-system), so there is no chicken-and-egg dependency on a node group and no
# idle baseline nodes. Once Karpenter is up (see modules/karpenter), it provisions
# all other capacity on demand.
#
# Because the controller runs on Fargate, it must authenticate via IRSA — EKS Pod
# Identity is not supported on Fargate. The v21 Karpenter submodule defaults to Pod
# Identity, so we turn the association off and inject an IRSA trust statement into
# the controller role it creates. That keeps the submodule's upstream-maintained
# controller policy (no hand-rolled IAM) while making the role assumable on Fargate.

locals {
  karpenter_namespace       = "kube-system"
  karpenter_service_account = "karpenter"

  # The public endpoint is intentionally enabled for this POC (testing without a
  # VPN, see variables.tf / README), but it is never left open to the world. When
  # public access is on we scope it to the IP running Terraform plus any explicitly
  # supplied CIDRs; when it is off the list is empty and the module ignores it.
  runner_public_cidr  = var.endpoint_public_access ? ["${chomp(data.http.runner_ip[0].response_body)}/32"] : []
  public_access_cidrs = concat(local.runner_public_cidr, var.endpoint_public_access_cidrs)
}

# Public IP of the machine running Terraform, used to lock the public EKS endpoint
# down to the operator / CI runner. Only fetched when public access is enabled, so
# a private-only run has no dependency on reaching the internet.
data "http" "runner_ip" {
  count = var.endpoint_public_access ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.23"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Private always on; public access is enabled for the POC but scoped to the
  # runner IP + supplied CIDRs (computed above) rather than 0.0.0.0/0.
  endpoint_private_access      = true
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = local.public_access_cidrs

  # Whoever runs `apply` gets cluster-admin via an EKS access entry.
  enable_cluster_creator_admin_permissions = true

  # Envelope-encrypt Kubernetes Secrets with a KMS key. v21 defaults this OFF
  # (encryption_config = {}); create_kms_key defaults true, so the module
  # provisions and wires a customer-managed key — required for the sensitive-data
  # posture in architecture/01-cloud-environment.md.
  encryption_config = {
    resources = ["secrets"]
  }

  # Ship control-plane logs to CloudWatch explicitly rather than relying on the
  # module default (architecture/02-network-design.md — visibility).
  enabled_log_types = ["audit", "api", "authenticator"]

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  # Core capabilities as EKS-managed add-ons.
  addons = {
    # VPC CNI with prefix delegation so pod density doesn't exhaust the subnet.
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = { most_recent = true }
    # CoreDNS pinned to Fargate so it schedules with no EC2 nodes present.
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate"
        resources = {
          requests = { cpu = "0.25", memory = "256M" }
          limits   = { cpu = "0.25", memory = "256M" }
        }
      })
    }
  }

  # Karpenter discovers the security group to attach to nodes by this tag
  # (EC2NodeClass securityGroupSelectorTerms in modules/karpenter).
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  # Serverless bootstrap compute for the controllers that must run before any
  # EC2 node exists. kube-system holds CoreDNS, Karpenter, and the add-on
  # controllers; their DaemonSet counterparts only land on Karpenter's EC2 nodes.
  fargate_profiles = {
    kube-system = {
      selectors = [{ namespace = local.karpenter_namespace }]
    }
  }

  tags = var.tags
}

# IRSA trust statement injected into the controller role's assume-role policy
# (alongside the submodule's default Pod Identity statement, which is harmless
# without an association). This is the only change needed to run the controller
# on Fargate — the controller policy itself stays maintained by the submodule.
data "aws_iam_policy_document" "karpenter_controller_irsa" {
  statement {
    sid     = "KarpenterControllerIRSA"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.karpenter_namespace}:${local.karpenter_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Karpenter infrastructure: the controller IAM role (with its upstream-maintained
# policy) plus node IAM role + instance profile, the SQS interruption queue +
# EventBridge rules (graceful drain on Spot reclaim), and the access entry that
# lets Karpenter-launched nodes join the cluster.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.23"

  cluster_name = module.eks.cluster_name

  # Fargate controller -> IRSA, not Pod Identity. Keep the submodule's controller
  # role + policy, but add the OIDC trust above so the SA can assume it.
  create_pod_identity_association         = false
  iam_role_source_assume_policy_documents = [data.aws_iam_policy_document.karpenter_controller_irsa.json]
  # Temporary as the underlying module exceeds the limit in the 6144 policy size
  # See https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3637
  enable_inline_policy = true

  enable_spot_termination = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

# Account/region-wide guarantee that every new EBS volume is encrypted at rest,
# whatever launch template or NodeClass requests it — belt-and-suspenders behind
# the explicit per-node encryption in the Karpenter EC2NodeClass. Scoped to this
# environment's own account (one account per environment, see architecture/01).
resource "aws_ebs_encryption_by_default" "this" {
  count   = var.enable_ebs_encryption_by_default ? 1 : 0
  enabled = true
}
