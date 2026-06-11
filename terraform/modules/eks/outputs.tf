# --- Cluster (consumed by the karpenter unit's k8s/helm providers) ---
output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Kubernetes version actually running."
  value       = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN (IRSA)."
  value       = module.eks.oidc_provider_arn
}

# --- Karpenter wiring (consumed by the karpenter unit's Helm releases) ---
output "karpenter_namespace" {
  description = "Namespace the Karpenter controller runs in."
  value       = local.karpenter_namespace
}

output "karpenter_service_account" {
  description = "Karpenter controller service account name."
  value       = local.karpenter_service_account
}

output "karpenter_controller_role_arn" {
  description = "Controller role ARN (IRSA trust) to annotate on the Karpenter service account."
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_iam_role_name" {
  description = "Node IAM role name referenced by the EC2NodeClass."
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_queue_name" {
  description = "SQS interruption queue name (settings.interruptionQueue)."
  value       = module.karpenter.queue_name
}
