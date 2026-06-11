# Dedicated per-environment VPC with the three-tier subnet layout from
# architecture/02-network-design.md:
#   - public      (/24): internet-facing ALB + NAT gateways
#   - private-app (/20): EKS nodes and pods (pods draw IPs from the subnet)
#   - private-data(/24): managed PostgreSQL only — no route to NAT or IGW
#
# Subnet CIDRs are derived from the VPC /16 to match the worked example in the
# doc (private-app 10.x.0/16/32.0/20, public 10.x.48-50.0/24, data 10.x.64-66.0/24).

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 app subnets: blocks 0,1,2 of the /16 split into /20s -> .0/.16/.32
  private_app_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  # /24 public subnets: offset to .48/.49/.50
  public_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 48 + i)]
  # /24 data subnets: offset to .64/.65/.66
  private_data_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 64 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # private-app tier (EKS nodes/pods)
  private_subnets = local.private_app_subnets
  # public tier (ALB + NAT)
  public_subnets = local.public_subnets
  # private-data tier (no NAT/IGW route — database subnet group)
  database_subnets                   = local.private_data_subnets
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  # Stateless NACL backstop hard-fencing the data tier (architecture/02): allow
  # only PostgreSQL + ephemeral return traffic, and only from inside the VPC —
  # everything else (and anything from the internet) is denied by the implicit
  # deny. A simple first cut; tighten the source to the app subnets later.
  database_dedicated_network_acl = true
  database_inbound_acl_rules = [
    { rule_number = 100, rule_action = "allow", protocol = "tcp", from_port = 5432, to_port = 5432, cidr_block = var.vpc_cidr },
    { rule_number = 110, rule_action = "allow", protocol = "tcp", from_port = 1024, to_port = 65535, cidr_block = var.vpc_cidr },
  ]
  database_outbound_acl_rules = [
    { rule_number = 100, rule_action = "allow", protocol = "tcp", from_port = 1024, to_port = 65535, cidr_block = var.vpc_cidr },
    { rule_number = 110, rule_action = "allow", protocol = "tcp", from_port = 5432, to_port = 5432, cidr_block = var.vpc_cidr },
  ]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs to CloudWatch for visibility (architecture/02-network-design.md).
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  # Public subnets host internet-facing load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Private-app subnets: internal LBs live here, and Karpenter discovers them
  # by this tag when it launches nodes (see modules/karpenter EC2NodeClass).
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = var.tags
}

# Endpoints for the high-volume paths only: S3 (gateway) and ECR (interface).
# These cover image pulls — the bulk of node egress — keeping that traffic on the
# AWS backbone and off NAT. Other AWS APIs still go via NAT; add more endpoints
# (sts, logs, …) later if NAT cost or a fully-private posture warrants it.
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.6"

  vpc_id = module.vpc.vpc_id

  create_security_group      = true
  security_group_name_prefix = "${var.cluster_name}-vpce-"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from within the VPC"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.private_route_table_ids])
      tags            = { Name = "${var.cluster_name}-s3" }
    }
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
  }

  tags = var.tags
}
