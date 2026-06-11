output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private-app subnet IDs (EKS nodes/pods)."
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs (ALB/NAT)."
  value       = module.vpc.public_subnets
}

output "database_subnets" {
  description = "Private-data subnet IDs (managed PostgreSQL)."
  value       = module.vpc.database_subnets
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}
