# ADR-0002: EKS with Argo CD for AWS compute (supersedes ADR-0001)

- **Status:** Accepted - **not yet applied**
- **Date:** 2026-10-07
- **Decision owner:** Srinidhi Sanjeevi
- **Supersedes:** ADR-0001 (ECS Fargate over EKS)
- **Applies to:** `terraform/aws/environments/eks-dev`

## Context

ADR-0001 chose ECS Fargate because of cost and team size. This decision reverses it for a different reason:
the project's objective is to show **one delivery model on both clouds**. With Fargate, Azure deploys by
Git commit through Argo CD while AWS deploys by `terraform apply` of an updated tag. ADR-0001 named that
exact asymmetry as its main cost and listed "a uniform GitOps flow across both clouds becomes a stated
requirement" as a revisit trigger. It now is.

## Decision

Run the same six services on **EKS**, deployed by Argo CD from the same Helm charts as Azure.
The Fargate code (`environments/fargate-dev`, `modules/ecs-service`, ...) stays in the repository and is
not deleted; only its running resources are destroyed, after EKS is verified.

## What changes and what does not

| | Before (Fargate) | After (EKS) |
|---|---|---|
| Deploy | CI commits tag to infra repo; a person runs `terraform apply` | CI commits tag to GitOps repo; Argo CD syncs |
| Rollback | revert + apply | `git revert` |
| Drift | none corrected | Argo `selfHeal` |
| Secrets | execution role injects at start | Secrets Store CSI + IRSA (same as Azure's CSI + workload identity) |
| Isolation | security group per caller | NetworkPolicy per service (the charts already ship them) |
| Observability | CloudWatch dashboards + alarms | Prometheus, Grafana, Loki, Alertmanager (same as Azure) |
| Unchanged | images, ECR, Secrets Manager, VPC, NAT + Elastic IP (Atlas allowlist), GitHub OIDC | |

## Cost - the part ADR-0001 got right and this decision accepts

Approximate, ap-south-1, on-demand, standard published pricing - verify in the AWS calculator before quoting:

| Item | Monthly |
|---|---|
| EKS control plane | ~$73 |
| 2 x m7i-flex.large nodes (Free Plan allows only free-tier-eligible types; t3.large is refused) | ~$140 |
| 2 x NLB (customer, admin) | ~$33 |
| EBS volumes | ~$5 |
| **Added** | **~$250** |

ADR-0001 recorded $103.44 of credits and a $74/month burn. At ~$250/month **added**, the EKS path is a short-lived
demonstration environment, not a standing one. It is tolerable only because the Fargate stack is destroyed
(~-$55) and the whole stack can be torn down after evaluation. Run it for the evaluation window, then destroy it.

## Consequences

**Positive:** one delivery model, one set of charts, one monitoring stack, one rollback story across both clouds.
**Negative:** an order of magnitude more to operate (add-ons, node patching, version upgrades); an EKS control
plane that bills while idle; two more things Terraform does not own (Argo CD, ingress), installed by a bootstrap script.

## Revisit triggers

- Credits cannot cover the evaluation window -> destroy `eks-dev`, re-apply `fargate-dev`.
- A requirement appears for scale-to-zero or per-request billing -> Fargate/Lambda again.
