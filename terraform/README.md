# EKS + Karpenter POC — Terragrunt layout

Infrastructure-as-code that stands up an **Amazon EKS cluster on the latest
Kubernetes version in a dedicated VPC**, deploys **Karpenter** with a node pool
that launches **both x86 and Graviton (arm64)** instances **Spot-first**, and
includes a developer demo for scheduling a pod onto either architecture.

It implements the Phase-1 compute and network design from the
[`architecture/`](../architecture/) documents, scoped down to a runnable POC:
**VPC → EKS → Karpenter → NodePool → demo workload.**

The code is organised as a modern **Terragrunt** blueprint (Stacks + Units).
Terragrunt orchestrates plain Terraform/OpenTofu modules — the underlying IaC is
still Terraform; Terragrunt adds the multi-layer, multi-account wiring around it.

---

## Why Terragrunt (and not plain Terraform)?

For a single throwaway state, plain Terraform/OpenTofu is simpler and Terragrunt
would be overhead. Terragrunt earns its place precisely because this design is
**multi-layer and multi-account** ([`01-cloud-environment.md`](../architecture/01-cloud-environment.md)).
What it buys us here, with the actual mechanism behind each point:

- **DRY backend & provider config.** The S3 backend and AWS provider are defined
  **once** in [`root.hcl`](root.hcl) and generated into every unit at runtime
  (`generate` blocks). Terraform backends can't take variables; Terragrunt
  generates them, so each layer gets a unique state key with zero copy-paste.
- **Per-layer state isolation.** VPC, EKS, and Karpenter each have their own
  state file. A Karpenter change can't corrupt VPC state, and blast radius stays
  small. Plain TF pushes you toward one big state or manual workspace juggling.
- **Cross-layer dependency DAG.** The EKS unit reads the VPC unit's outputs
  (`dependency.vpc.outputs.private_subnets`); the Karpenter unit reads EKS's.
  `terragrunt stack run apply` builds the graph and applies **vpc → eks →
  karpenter** in order. Plain TF has no cross-state ordering.
- **Multi-account by configuration.** The generated provider is where a
  per-account `assume_role` goes. The *same* blueprint targets dev/staging/prod
  by swapping a per-account `account.hcl` — nothing else changes.
- **A variable cascade.** Context flows account → region → env → unit through
  `read_terragrunt_config`, `inputs`, and a stack's `values`, instead of
  duplicating `.tfvars` per environment.
- **Stacks + Units = one blueprint, many environments.**
  [`live/dev/terragrunt.stack.hcl`](live/dev/terragrunt.stack.hcl) instantiates
  the shared [`catalog/units`](catalog/units) with dev values. A `live/prod`
  stack is a copy of that one file with prod values — the units and modules are
  reused verbatim. (Stacks are GA as of Terragrunt 1.0.)

---

## Layout

```
terraform/
├── root.hcl                      # S3 backend + AWS provider generation + common tags
├── live/
│   └── dev/
│       ├── env.hcl               # dev context: region, cluster name, CIDR, K8s version
│       └── terragrunt.stack.hcl  # instantiates vpc → eks → karpenter for dev
├── catalog/
│   └── units/                    # reusable unit templates (the blueprint)
│       ├── vpc/                  #   network
│       ├── eks/                  #   cluster + Karpenter IAM/SQS scaffolding
│       └── karpenter/            #   controller + NodePool (generates k8s/helm providers)
├── modules/                      # local composition modules the units point at
│   ├── vpc/                      #   wraps terraform-aws-modules/vpc
│   ├── eks/                      #   wraps terraform-aws-modules/eks + karpenter submodule + controller IRSA
│   └── karpenter/                #   helm_release(karpenter) + local NodePool/EC2NodeClass chart
│       └── charts/karpenter-nodes/
└── examples/
    └── workloads/                # the developer demo (x86 / arm64 / multi-arch)
```

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| OpenTofu | `1.12.1` | Pinned in `.opentofu-version`, managed by `tenv` (below). |
| Terragrunt | `1.0.7` | Pinned in `.terragrunt-version`, managed by `tenv`. Stacks GA; root config is `root.hcl`. |
| tenv | latest | Version manager that reads the two files above and installs the right binaries. |
| AWS CLI v2 | latest | Used for `aws eks get-token` (cluster auth) and credentials. |
| kubectl | matches cluster | For the demo. |
| Helm | ≥ 3.x | Only if you want to inspect the charts locally. |

**Tool versions are managed with [`tenv`](https://github.com/tofuutils/tenv)** —
the cleanest way to pin and auto-install the OpenTofu/Terragrunt binaries per
project. The exact versions live in `terraform/.opentofu-version` and
`terraform/.terragrunt-version`; `tenv` reads them automatically and installs/uses
the right binary, so the whole team and CI run identical tooling. One-time setup:

```bash
brew install tenv          # or: see tenv install docs
cd terraform
tenv tofu install          # installs the version in .opentofu-version
tenv terragrunt install    # installs the version in .terragrunt-version
```

After that, `tofu` and `terragrunt` resolve to the pinned versions automatically
inside this directory tree. Bump a version by editing the corresponding
`.*-version` file — the same deliberate, reviewed change as a provider bump.

AWS credentials with permissions to create VPC, EKS, IAM, and SQS resources must
be configured (`aws sts get-caller-identity` should succeed). The S3 state bucket
is created by the one-time bootstrap step below — not by hand.

---

## Usage

All commands run from the environment directory:

```bash
cd terraform/live/dev

# 1. Materialise the stack: renders vpc/eks/karpenter units into .terragrunt-stack/
terragrunt stack generate

# 2. Bootstrap state backend (FIRST RUN ONLY): create the S3 state bucket with
#    versioning, encryption, and lock support, from the remote_state config in
#    root.hcl. Idempotent — skips creation when the bucket already exists.
terragrunt backend bootstrap --all

# 3. Review the plan across all layers (applied in dependency order)
terragrunt stack run plan

# 4. Apply: VPC, then EKS (Fargate-hosted Karpenter; endpoint scoped to your IP),
#    then the Karpenter controller + default NodePool
terragrunt stack run apply

# Aggregate outputs across the stack
terragrunt stack output
```

> Step 2 is a one-time setup per account/region. `backend bootstrap` is a
> per-unit operation; `--all` simply runs it across every unit the stack
> generated (`terragrunt find` from this dir lists them). All three units share
> **one** state bucket — only the state key differs — so the bucket is created on
> the first unit and the rest are no-ops; bootstrapping a single unit is
> equivalent. If you'd rather not run it separately, append `--backend-bootstrap`
> to the apply (`terragrunt stack run apply --backend-bootstrap`) and Terragrunt
> creates the bucket inline on first use. The bucket is **not** torn down by
> `destroy` — remove it manually for a truly clean slate.

**Teardown** (delete demo workloads first so Karpenter deprovisions the nodes it
launched, then destroy in reverse dependency order):

```bash
kubectl delete -f ../../examples/workloads/   # if you ran the demo
terragrunt stack run destroy
```

> A single layer can also be driven directly, e.g.
> `terragrunt apply --working-dir .terragrunt-stack/vpc`.

---

## Reaching the cluster

The architectural target is a **private-only** endpoint reached over an
identity-aware VPN — a **Tailscale subnet router** (or an **SSM-fronted bastion**)
advertising the cluster endpoint into the tailnet
([`02-network-design.md`](../architecture/02-network-design.md)). That access layer
is documented in the architecture but not built in this POC.

So that the cluster can be reached for **testing without first standing up that
VPN path**, this POC ships with the public endpoint **deliberately enabled** in
[`live/dev/env.hcl`](live/dev/env.hcl) (`endpoint_public_access = true`). It is
**not** open to the world: the EKS module auto-detects the **public IP of the
machine running Terraform** and allows only that `/32`, plus any extra ranges in
`endpoint_public_access_cidrs` (e.g. an office or CI egress range) — never
`0.0.0.0/0`. The private endpoint is always on as well, so the in-VPC access path
keeps working unchanged.

```hcl
# live/dev/env.hcl
endpoint_public_access       = true        # POC testing; set false for private-only
endpoint_public_access_cidrs = []          # runner IP is always added; add office/CI ranges here
```

Point `kubectl` at the cluster (works from any allowed CIDR):

```bash
aws eks update-kubeconfig --name innovate-dev --region eu-central-1
```

To move to the target posture, set `endpoint_public_access = false` and reach the
private endpoint over the VPN/SSM path above.

---

## Developer demo — run a pod on x86 or Graviton

A developer chooses the architecture with a single `nodeSelector` on
`kubernetes.io/arch`. Karpenter sees the pending pod, launches a matching node
(Spot-first) from the default NodePool, and schedules it.

```bash
# x86 (Intel/AMD)
kubectl apply -f ../../examples/workloads/deploy-amd64.yaml

# Graviton (arm64) — same multi-arch image, only the selector differs
kubectl apply -f ../../examples/workloads/deploy-arm64.yaml

# No preference — Karpenter picks the cheapest (usually Graviton Spot)
kubectl apply -f ../../examples/workloads/deploy-multiarch.yaml
```

Watch Karpenter provision capacity and confirm placement:

```bash
kubectl get nodeclaims                       # nodes Karpenter is launching
kubectl get pods -o wide                      # which node each pod landed on
kubectl get nodes -L kubernetes.io/arch -L karpenter.sh/capacity-type
```

You should see `hello-amd64` pods on an `amd64` node and `hello-arm64` pods on an
`arm64` node, most of them `capacity-type=spot`.

---

## How the pieces fit

- **Bootstrap with no node group.** The cluster starts with **zero** managed
  nodes. **CoreDNS and the Karpenter controller run on AWS Fargate** (a single
  `kube-system` Fargate profile), so there's no chicken-and-egg dependency on a
  node group and no idle baseline cost. Once Karpenter is up it provisions all
  other capacity on demand.
- **Why the controller uses IRSA, not Pod Identity.** EKS **Pod Identity is not
  supported on Fargate**, and the `terraform-aws-modules/eks` v21 Karpenter
  submodule defaults to Pod Identity. So we keep the submodule (it creates the
  **controller role + its upstream-maintained policy**, node IAM role, instance
  profile, SQS interruption queue, and access entry), turn the Pod Identity
  association **off**, and inject an **IRSA trust statement** into the controller
  role via the submodule's `iam_role_source_assume_policy_documents`. That's the
  Fargate-compatible path with **no hand-rolled IAM policy** — the controller
  permissions stay maintained upstream and current with the module.
- **Spot-first, both architectures.** One NodePool allows `amd64` + `arm64` and
  `spot` + `on-demand`. Karpenter's price-capacity-optimized allocation prefers
  Spot (cheaper) and falls back to on-demand when Spot is short — Spot-first
  without a second pool. A diversified instance set keeps the Spot pool deep, and
  consolidation continuously bin-packs to the cheapest fit.
- **CRDs via a Helm release, not `kubernetes_manifest`.** The NodePool and
  EC2NodeClass ship as a small local chart applied **after** the controller
  (`depends_on`). This avoids `kubernetes_manifest`'s plan-time dry-run, which
  fails when the CRD it references was only just installed in the same run.

---

## Additional notes — GitOps handover to Argo CD (recommended target)

Helm-via-Terraform here is a **bootstrap**, not the steady state. The recommended
target ([`03-compute-platform.md`](../architecture/03-compute-platform.md)) is to
let **Argo CD** own everything inside the cluster:

1. Bootstrap **Argo CD itself** once via the Helm provider, with a `lifecycle`
   `ignore_changes` so Terraform stops fighting Argo CD's self-updates.
2. Point Argo CD at an **app-of-apps** repo. From there it manages **itself**,
   **Karpenter and its NodePools**, monitoring, ingress, and the client
   applications — declaratively, with drift detection and auditable, revertible
   changes.
3. The Karpenter controller and the NodePool/EC2NodeClass objects move from these
   Helm releases into Argo CD Applications. Terraform's job shrinks to the cloud
   primitives that must exist *before* a cluster can be reconciled: **VPC, IAM,
   EKS, and the Karpenter IAM/SQS scaffolding.**

Clean separation of concerns: **Terraform owns cloud infrastructure; Argo CD owns
in-cluster state.**

---

## Versions & pinning

**Why pin at all?** Pinning is not the opposite of "using the latest" — we pin
**to** the latest and commit OpenTofu's `.terraform.lock.hcl`. That way every run,
teammate, and CI pipeline resolves the *same* provider/module versions and an
upstream release can't silently change a plan or break the build. The `~> X.0`
form tracks the latest minor/patch within a major while blocking a surprise
breaking major. Everything below is pinned to its **current latest** as of authoring.

Bumping is a deliberate, reviewed action:

```bash
cd terraform/live/dev
terragrunt run --all init -upgrade   # re-resolve to newest allowed, update lockfiles
```

| Component | Pin | Latest at authoring | Notes |
|-----------|-----|---------------------|-------|
| OpenTofu | `1.12.1` (`.opentofu-version`) | 1.12.1 | Managed by `tenv`; module floor is `>= 1.6`. |
| Terragrunt | `1.0.7` (`.terragrunt-version`) | 1.0.7 | Managed by `tenv`; Stacks GA. |
| EKS Kubernetes | `1.34` (in `env.hcl`) | 1.34 | Bump the string to upgrade. |
| AWS provider | `~> 6.0` | 6.49.0 | |
| Helm provider | `~> 3.0` | 3.2.0 | v3 attribute-style config. |
| `terraform-aws-modules/eks/aws` | `~> 21.0` | 21.23.0 | Cluster + Karpenter submodule (controller role/policy, node role, SQS). |
| `terraform-aws-modules/vpc/aws` | `~> 6.0` | 6.6.1 | |
| Karpenter chart | `1.13.0` | 1.13.0 | NodePool `karpenter.sh/v1`, EC2NodeClass `karpenter.k8s.aws/v1`. |
| AMI alias | `bottlerocket@v1.62.0` | 1.62.0 | Pinned Bottlerocket (minimal/immutable). Bump the version to upgrade. |

The Karpenter controller IAM policy is **not** vendored here — it comes from the
eks Karpenter submodule, so it stays current with the module rather than drifting
in our tree. We only add a small IRSA trust statement (see *How the pieces fit*).
