terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Used only to detect the Terraform runner's public IP so the public EKS
    # endpoint can be scoped to it instead of 0.0.0.0/0.
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}
