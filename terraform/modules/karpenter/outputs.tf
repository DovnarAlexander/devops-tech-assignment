output "karpenter_release_name" {
  description = "Helm release name of the Karpenter controller."
  value       = helm_release.karpenter.name
}

output "karpenter_release_version" {
  description = "Karpenter chart version installed."
  value       = helm_release.karpenter.version
}

output "node_pool_name" {
  description = "Name of the default NodePool registered."
  value       = "default"
}
