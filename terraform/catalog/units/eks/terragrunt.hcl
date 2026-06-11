# Unit: eks — the cluster plus the IAM/SQS scaffolding Karpenter needs.
#
# Depends on the vpc unit for its network. `dependency` reads the vpc unit's
# outputs and makes Terragrunt apply vpc before eks (the dependency DAG).

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules//eks"
}

dependency "vpc" {
  config_path = values.vpc_path

  # Lets `plan`/`validate` run before the vpc unit is applied.
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-00000000000000000", "subnet-00000000000000001", "subnet-00000000000000002"]
  }
}

inputs = {
  cluster_name                 = values.cluster_name
  kubernetes_version           = values.kubernetes_version
  endpoint_public_access       = values.endpoint_public_access
  endpoint_public_access_cidrs = values.endpoint_public_access_cidrs

  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnets
}
