# root.hcl — the single root configuration every unit includes.
#
# This is where the cross-cutting, DRY-by-design concerns live: remote state,
# the AWS provider, and the tags every resource inherits. A unit (vpc, eks,
# karpenter) is just a thin wrapper that includes this file and supplies inputs.
#
# Modern Terragrunt (>= 1.0) names the root config `root.hcl` rather than
# `terragrunt.hcl` so it can never be confused with a unit.

locals {
  # Environment context. The stack file passes most values into units directly
  # (see live/<env>/terragrunt.stack.hcl), but the backend and provider need a
  # few of them here too, so we read env.hcl from the nearest parent.
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals

  account_id = get_aws_account_id()
  region     = local.env.aws_region

  # State bucket is per account+region. It is created by the one-time
  # `terragrunt backend bootstrap` step (see README), with versioning, encryption,
  # and lock support enabled from the config below.
  state_bucket = "tfstate-${local.env.environment}-${local.account_id}-${local.region}"

  common_tags = {
    Project     = "innovate-inc"
    Environment = local.env.environment
    ManagedBy   = "terragrunt"
  }
}

# --- Remote state -----------------------------------------------------------
# One S3 backend definition, inherited by every unit. Terragrunt computes a
# unique state key per unit from its path, so layers never share state and the
# blast radius of any single apply stays small.
#
# `use_lockfile = true` uses S3-native conditional-write locking (no DynamoDB
# table required on modern Terraform/OpenTofu).
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = local.state_bucket
    key          = "${path_relative_to_include()}/tf.tfstate"
    region       = local.region
    encrypt      = true
    use_lockfile = true
  }
}

# --- Provider ---------------------------------------------------------------
# Generated once here and dropped into every unit's working dir. For a real
# multi-account setup this is also where an `assume_role { role_arn = ... }`
# block (driven by a per-account account.hcl) would go — the same blueprint
# then targets dev/staging/prod with different roles and nothing else changes.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = ${jsonencode(local.common_tags)}
      }
    }
  EOF
}

# Inputs merged into every unit. Unit-specific inputs come from the stack's
# `values` and from `dependency` outputs.
inputs = {
  environment = local.env.environment
  aws_region  = local.region
  tags        = local.common_tags
}
