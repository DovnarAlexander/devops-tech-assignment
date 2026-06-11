# Karpenter bootstrap: install the controller, then register one NodePool +
# EC2NodeClass that can launch both x86 and Graviton, Spot-first.
#
# Both are Helm releases. The NodePool/EC2NodeClass ship as a tiny local chart
# rather than `kubernetes_manifest` resources, because that resource does a
# server-side dry-run at plan time and fails when the CRD it references was only
# just installed by the controller chart in the same run. A Helm release of the
# manifests, ordered after the controller with depends_on, sidesteps that.
#
# NOTE: Helm here is a *bootstrap*. The recommended target is to hand these
# objects to Argo CD (see terraform/README.md) — Terraform owns the cloud
# primitives, Argo CD owns in-cluster state.
# After taking it under the ArgoCD management will start ignoring any changes using
# terraform meta attributes `ignore_changes`

# The Karpenter chart lives on ECR Public. Anonymous pulls are rate-limited and
# fail outright if a stale public-ECR token is cached in the environment
# (403 "authorization token has expired"). Fetching a fresh token makes the pull
# deterministic regardless of local docker/helm login state. The ECR Public auth
# API is only served from us-east-1, so the data source overrides region there
# (AWS provider v6 per-resource region) — no separate aliased provider needed.
data "aws_ecrpublic_authorization_token" "token" {
  region = "us-east-1"
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = var.karpenter_chart_version
  namespace           = var.karpenter_namespace

  # CRDs ship with this chart; let Helm manage their upgrades.
  values = [yamlencode({
    serviceAccount = {
      name = var.karpenter_service_account
      annotations = {
        "eks.amazonaws.com/role-arn" = var.karpenter_controller_role_arn
      }
    }
    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = var.karpenter_queue_name
    }
    controller = {
      resources = {
        requests = { cpu = "1", memory = "1Gi" }
        limits   = { memory = "1Gi" }
      }
    }
  })]

  # Wait for the controller Deployment to be Available so the CRDs are
  # registered before the NodePool/EC2NodeClass release applies.
  wait = true
}

resource "helm_release" "karpenter_nodes" {
  name      = "karpenter-nodes"
  chart     = "${path.module}/charts/karpenter-nodes"
  namespace = var.karpenter_namespace

  values = [yamlencode({
    clusterName = var.cluster_name
    nodeRole    = var.karpenter_node_iam_role_name
    amiAlias    = var.ami_alias
    tags        = var.tags
  })]

  depends_on = [helm_release.karpenter]
}
