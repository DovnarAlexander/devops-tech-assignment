terraform {
  required_version = ">= 1.6"

  required_providers {
    # Helm installs the releases (its provider config is generated in the
    # karpenter unit, v3 attribute syntax). AWS is used only to fetch a fresh
    # ECR Public auth token for pulling the Karpenter chart.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
