variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (the latest available is set in env.hcl)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in (from the vpc unit)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private-app subnet IDs for nodes, Fargate, and the control-plane ENIs."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = <<-EOT
    Expose the EKS API endpoint publicly. Target state is private-only, reached
    over a Tailscale subnet router / SSM bastion (architecture/02-network-design.md).
    Enabled in this POC for testing without VPN access; access is always scoped to
    the Terraform runner's IP plus endpoint_public_access_cidrs — never 0.0.0.0/0.
  EOT
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = <<-EOT
    Extra CIDRs allowed to reach the public endpoint, ON TOP of the Terraform
    runner's auto-detected public IP (e.g. an office or CI egress range). Empty
    means "only the machine running the apply". Never set to 0.0.0.0/0.
  EOT
  type        = list(string)
  default     = []
}

variable "enable_ebs_encryption_by_default" {
  description = <<-EOT
    Turn on account/region-wide EBS encryption-by-default. Account-scoped setting;
    leave on for a dedicated per-environment account (architecture/01). Set false
    if several environments share one account and another stack already manages it.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
