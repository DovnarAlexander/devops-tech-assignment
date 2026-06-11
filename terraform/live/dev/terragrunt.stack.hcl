# terragrunt.stack.hcl — the dev environment blueprint.
#
# A stack is a generator: `terragrunt stack generate` materializes these unit
# blocks into a `.terragrunt-stack/` directory (one real unit per block), and
# `terragrunt stack run <cmd>` runs them in dependency order (vpc → eks →
# karpenter). The units themselves are sourced from the shared catalog, so this
# file is the only thing that differs between environments.

locals {
  env   = read_terragrunt_config("env.hcl").locals
  units = "${dirname(find_in_parent_folders("root.hcl"))}/catalog/units"
}

unit "vpc" {
  source = "${local.units}/vpc"
  path   = "vpc"

  values = {
    cluster_name = local.env.cluster_name
    vpc_cidr     = local.env.vpc_cidr

    # Per-environment tunable: optional override, safe non-prod default.
    single_nat_gateway = try(local.env.single_nat_gateway, true)
  }
}

unit "eks" {
  source = "${local.units}/eks"
  path   = "eks"

  values = {
    cluster_name       = local.env.cluster_name
    kubernetes_version = local.env.kubernetes_version

    # Per-environment tunable: optional override, private-only default.
    endpoint_public_access = try(local.env.endpoint_public_access, false)
    # Extra CIDRs allowed on the public endpoint (the runner IP is always added).
    endpoint_public_access_cidrs = try(local.env.endpoint_public_access_cidrs, [])

    # sibling unit this one depends on (relative to the generated dir)
    vpc_path = "../vpc"
  }
}

unit "karpenter" {
  source = "${local.units}/karpenter"
  path   = "karpenter"

  values = {
    cluster_name = local.env.cluster_name

    # sibling unit this one depends on
    eks_path = "../eks"
  }
}
