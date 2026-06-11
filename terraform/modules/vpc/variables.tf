variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name this VPC hosts. Used for Karpenter/ELB subnet discovery tags."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Each environment uses its own non-overlapping /16."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to spread the three subnet tiers across."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway (cheap, non-prod). Prod uses one NAT per AZ."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}
