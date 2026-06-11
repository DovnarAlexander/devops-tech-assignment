# Unit: karpenter — install the controller and register the default NodePool.
#
# This is the only layer that talks to the Kubernetes API, so it's the only one
# that needs the helm + kubernetes providers. They are generated here (not in
# root.hcl) because they authenticate against the specific cluster the eks unit
# produced — via `aws eks get-token`, so there are no long-lived kubeconfigs.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.aws_region
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules//karpenter"
}

dependency "eks" {
  config_path = values.eks_path

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
  mock_outputs = {
    cluster_name                       = "mock"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jaw==" # base64("mock")
    karpenter_namespace                = "kube-system"
    karpenter_service_account          = "karpenter"
    karpenter_controller_role_arn      = "arn:aws:iam::000000000000:role/mock"
    karpenter_node_iam_role_name       = "mock-node-role"
    karpenter_queue_name               = "mock-queue"
  }
}

# Helm provider (v3) authenticated with a short-lived token via `aws eks
# get-token` — no long-lived kubeconfig. v3 uses attribute syntax
# (`kubernetes = { ... exec = { ... } }`).
generate "helm_provider" {
  path      = "provider_helm.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority_data}")
        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_name}", "--region", "${local.region}"]
        }
      }
    }
  EOF
}

inputs = {
  cluster_name = values.cluster_name

  karpenter_namespace           = dependency.eks.outputs.karpenter_namespace
  karpenter_service_account     = dependency.eks.outputs.karpenter_service_account
  karpenter_controller_role_arn = dependency.eks.outputs.karpenter_controller_role_arn
  karpenter_node_iam_role_name  = dependency.eks.outputs.karpenter_node_iam_role_name
  karpenter_queue_name          = dependency.eks.outputs.karpenter_queue_name
}
