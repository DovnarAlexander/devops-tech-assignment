# Unit: vpc — the dedicated network for one environment.
#
# Wraps the local modules/vpc composition (which in turn wraps the upstream
# terraform-aws-modules/vpc). Inputs come from the stack's `values` plus the
# shared inputs injected by root.hcl (environment, region, tags).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules//vpc"
}

inputs = {
  cluster_name       = values.cluster_name
  vpc_cidr           = values.vpc_cidr
  single_nat_gateway = values.single_nat_gateway
}
