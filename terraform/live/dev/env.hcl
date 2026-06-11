# env.hcl — per-environment context for the `dev` POC.
#
# A second environment (staging, prod) is a copy of this directory with
# different values here and, in a multi-account setup, its own account.hcl.
# The stack blueprint (terragrunt.stack.hcl) and the catalog units are reused
# unchanged — that is the whole point of the layout.

locals {
  environment  = "dev"
  aws_region   = "eu-central-1"
  cluster_name = "innovate-dev"

  # Latest EKS Kubernetes version (see architecture/03-compute-platform.md).
  # Bump this string to upgrade — non-prod leads prod to de-risk the jump.
  kubernetes_version = "1.36"

  # Dev gets its own non-overlapping /16 (architecture/02-network-design.md).
  vpc_cidr = "10.2.0.0/16"

  # ---- Per-environment tunables (the stack propagates these into units) -------
  # These are the knobs that differ between environments. The stack blueprint and
  # catalog units are identical across envs; only these values change. Each is an
  # optional override with a safe default in the stack — set them here to deviate.

  # One shared NAT gateway (cheap) in non-prod. PRODUCTION sets this to `false`
  # for one NAT gateway per AZ, so an AZ failure can't take out egress
  # (architecture/02-network-design.md).
  single_nat_gateway = true

  # Public EKS endpoint is intentionally ENABLED for this POC so the cluster can
  # be reached for testing without first standing up the VPN path. It is NOT open
  # to the world: the module scopes it to the IP running Terraform plus the extra
  # CIDRs below. Target state is private-only over a Tailscale subnet router / SSM
  # bastion (architecture/02-network-design.md) — flip this to false to get there.
  endpoint_public_access = true

  # Extra CIDRs allowed on the public endpoint, on top of the runner's own IP
  # (e.g. ["203.0.113.0/24"] for an office/CI range). Empty = runner IP only.
  endpoint_public_access_cidrs = []
}
