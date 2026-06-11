variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "karpenter_namespace" {
  description = "Namespace the controller runs in (shares the kube-system Fargate profile)."
  type        = string
  default     = "kube-system"
}

variable "karpenter_service_account" {
  description = "Karpenter controller service account name."
  type        = string
  default     = "karpenter"
}

variable "karpenter_controller_role_arn" {
  description = "IRSA role ARN annotated on the controller service account."
  type        = string
}

variable "karpenter_node_iam_role_name" {
  description = "Node IAM role name referenced by the EC2NodeClass."
  type        = string
}

variable "karpenter_queue_name" {
  description = "SQS interruption queue name (settings.interruptionQueue)."
  type        = string
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm chart version."
  type        = string
  default     = "1.13.0"
}

variable "ami_alias" {
  description = "EC2NodeClass AMI alias. Pinned to a specific Bottlerocket release so AMI bumps are reviewed."
  type        = string
  default     = "bottlerocket@v1.62.0"
}

variable "tags" {
  description = "Tags applied to Karpenter-launched EC2 instances."
  type        = map(string)
  default     = {}
}
