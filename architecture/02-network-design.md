<sub>[← Cloud Environment](01-cloud-environment.md) · [Index](README.md) · [Compute Platform →](03-compute-platform.md)</sub>

# 2. Network Design

Each environment account gets **one VPC** in a single AWS region, spread across **three Availability Zones** for high availability. The VPC is that environment's network boundary — environments never share one. We plan **non-overlapping** CIDR ranges so the VPCs can be peered or attached to a Transit Gateway later without renumbering.

## Phase 1 — VPC layout (per environment)

A standard three-tier subnet layout keeps what's reachable from the internet separate from what must never be:

![Runtime architecture — Route 53 splits to CloudFront/S3 and ALB; ALB reaches the in-cluster ingress controller, pods, and Aurora across three private tiers](diagrams/network-runtime.svg)

| Tier                | Holds                                   | Internet access                                  |
| ------------------- | --------------------------------------- | ------------------------------------------------ |
| **Public**          | Internet-facing ALB, NAT gateways       | Inbound + outbound via Internet Gateway          |
| **Private — app**   | EKS worker nodes and pods               | Outbound only, via NAT; no inbound from internet |
| **Private — data**  | Managed PostgreSQL (+ optional Redis)   | None — no route to NAT or IGW                    |

Design notes:

- **Ingress path.** Route 53 splits traffic by **domain**, not by path at the edge. The frontend (`app.example.com`) is served by **CloudFront + S3** as static assets. The API (`api.example.com`) goes to an internet-facing **ALB (with WAF and ACM TLS)**, which forwards everything to an **in-cluster ingress controller** (target-type `IP`). The ingress controller handles the detailed L7 routing — specific routes, API versions, and later canary or header-based rules — so routing lives in the cluster where the app team owns it. The ALB just has to reach the controller. Nodes, pods, and the database never get public IPs.
- **Egress.** App-tier nodes reach the internet only through NAT. Production uses **one NAT gateway per AZ** so an AZ failure doesn't take out egress; non-prod uses a **single NAT gateway** to save money.
- **VPC endpoints.** Interface and gateway endpoints for **ECR** and **S3** keep image pulls on the AWS backbone. That lowers NAT cost and keeps the high-volume registry traffic off the public internet.
- **Caching (optional, recommended).** Caching wasn't part of the original ask, but it's worth adding as traffic grows. A managed **ElastiCache (Redis)** cluster in the data tier handles session and read caching, with the same private placement and security-group treatment as the database. Start without it and turn it on when the API needs it.
- **IP planning.** The private **app subnets are sized large**: the VPC CNI assigns pod IPs straight from the subnet, and **prefix delegation** on the CNI stretches that further, so pod density doesn't run the subnet out of addresses.

**Addressing.** Every environment gets its **own, non-overlapping `/16`** so the VPCs can be peered or joined to a Transit Gateway later without renumbering — for example prod `10.0.0.0/16`, staging `10.1.0.0/16`, dev `10.2.0.0/16`. Inside a VPC, the private **app subnets must be at least a `/20`** (~4,091 usable IPs) because pods draw their IPs from the subnet via the VPC CNI; public and data subnets stay small. A worked example for the dev VPC (`10.2.0.0/16`), one subnet per tier per AZ across three AZs:

| Tier            | AZ-a          | AZ-b          | AZ-c          | Mask  | Usable | Why this size                                |
| --------------- | ------------- | ------------- | ------------- | ----- | ------ | -------------------------------------------- |
| Public          | 10.2.48.0/24  | 10.2.49.0/24  | 10.2.50.0/24  | `/24` | ~251   | Only the ALB and NAT gateways live here      |
| Private — app   | 10.2.0.0/20   | 10.2.16.0/20  | 10.2.32.0/20  | `/20` | ~4,091 | Pods get their IPs from the subnet (VPC CNI) |
| Private — data  | 10.2.64.0/24  | 10.2.65.0/24  | 10.2.66.0/24  | `/24` | ~251   | Aurora/RDS and the optional Redis only       |

The rest of the `/16` (here `10.2.51.0`–`10.2.63.255` and `10.2.67.0` onward) stays free for larger app subnets or extra tiers. Staging and prod use the same layout in their own `/16`.

## Securing the network

Security is layered, so no single control has to hold on its own:

- **Security groups (stateful, the primary control).** Least-privilege chaining: WAF/CloudFront → ALB SG → node SG on app ports only → database SG on **5432 only** from the node SG. The database accepts connections from nothing else.
- **NACLs (stateless backstop).** Coarse subnet-level rules, mainly to hard-fence the data tier.
- **AWS WAF** on CloudFront — managed rule sets for common web exploits (OWASP) plus rate-based rules to blunt volumetric and credential-stuffing attacks.
- **TLS everywhere at the edge.** ACM certificates terminate TLS at CloudFront and the ALB; HTTP redirects to HTTPS.
- **Private data path.** The data tier has no route to the internet in either direction, so sensitive data never crosses a public subnet.
- **EKS API access.** The cluster endpoint is **private-only from Phase 1** — never exposed to the internet. Engineers and CI reach it through the access path below.
- **Visibility.** VPC Flow Logs are on per VPC, and GuardDuty (org-wide, from [Cloud Environment](01-cloud-environment.md)) watches VPC, DNS, and flow telemetry for anomalies.

## Operator and developer access

The EKS endpoint and data stores are private, so engineers, `kubectl`, and CI need one controlled, audited way into the VPC — not a public entry point.

**Preferred — Tailscale.** Tailscale is a WireGuard-based mesh VPN, cloud-native and free for small teams. We run a Tailscale **subnet router** in each VPC, deployed as an **Auto Scaling Group of one small Graviton instance** (`t4g.small`, min = max = desired = 1) so it self-heals if the instance or its AZ fails — cheap, with no appliance to babysit (instance size is easy to bump later). The router advertises the private ranges — the EKS API endpoint, plus break-glass access to the database — into the tailnet. Access is governed by **Tailscale ACLs tied to IdP / IAM Identity Center groups**, so each user gets per-resource, per-port access with MFA. No VPN appliance to run, no certificates to rotate, no public ports. This is what keeps the cluster endpoint private from day one without a bastion fleet.

**Alternatives.** The same result works with any managed or self-hosted VPN (AWS Client VPN, OpenVPN, WireGuard) or with **bastion/jump hosts fronted by AWS Systems Manager Session Manager** — no inbound ports, no SSH keys, full session audit — which suits teams already standardized on SSM. The architecture doesn't depend on the specific tool, only on having one identity-aware, audited way in.

## Target state

- **Tighter zero-trust access** — Tailscale ACLs move to per-namespace / per-service granularity with device-posture checks, and access reviews run automatically against IdP group membership.
- **Multi-region** VPCs with Route 53 health-checked failover (active-passive) for disaster recovery; promoted to active-active if latency or RTO targets demand it.
- **East-west encryption** via a service mesh (mTLS between pods), moving from edge-only TLS toward zero-trust for data in transit.
- **Centralized egress / inspection** (AWS Network Firewall in the optional Network account, behind a Transit Gateway) — added only when account sprawl makes per-VPC NAT and per-VPC rules the bigger cost.

## Trade-offs

| Decision (Phase 1)                              | We gain                                   | We give up / mitigation                                                                                |
| ----------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Single NAT gateway in non-prod                  | Lower cost while traffic is low           | An AZ NAT outage stops non-prod egress. *Mitigated:* prod runs one NAT per AZ.                          |
| Private-only EKS endpoint via Tailscale         | No public control-plane exposure; zero-trust access | An access path to operate. *Mitigated:* Tailscale is free/managed for small teams; SSM-bastion is a drop-in fallback. |
| Edge-only TLS, no service mesh                  | Much less operational complexity          | No automatic east-west encryption. *Mitigated:* private subnets + SGs constrain east-west; mesh later. |
| Single region, Multi-AZ                         | Meets HA needs at a fraction of the cost  | No cross-region survival yet. *Mitigated:* DR is a [Database](04-database.md) concern; multi-region at target. |

Because the CIDRs don't overlap and each environment has its own VPC, moving to multi-region, private endpoints, or centralized egress is **additive** — none of it needs re-addressing or rebuilding the Phase 1 networks.

---

<sub>[← Cloud Environment](01-cloud-environment.md) · [Index](README.md) · [Compute Platform →](03-compute-platform.md)</sub>
