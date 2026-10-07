# ADR-0001: ECS Fargate for AWS compute, not EKS

- **Status:** Accepted
- **Date:** 2026-10-07
- **Decision owner:** Srinidhi Sanjeevi
- **Applies to:** `terraform/aws/environments/fargate-dev`

## Context

HomeEase is a home-services booking platform: six stateless Node.js services
(backend, admin-backend, frontend, admin-frontend, payment-service,
notification-service) behind an ALB and CloudFront, with MongoDB as the data
store and images in Azure Blob.

Three facts constrained the AWS compute choice:

1. **Team size is one engineer.** There is no platform team to own a cluster.
2. **Azure already runs Kubernetes.** The same six services run on AKS with
   Helm and Argo CD GitOps. Kubernetes capability is demonstrated there, so the
   AWS side does not need to prove it again.
3. **The AWS account runs on promotional credits, not an open budget.** As of
   2026-10-07: **$103.44 credits remaining, expiring in 71 days (2026-12-15)**,
   against a forecast spend of **$74.14/month**. That is roughly six weeks of
   runway at the current burn rate.

No workload in this project requires a Kubernetes-specific capability. There
are no operators, no custom resource definitions, no service mesh, no
DaemonSets, no GPU scheduling, and no multi-tenant isolation requirement.

## Decision

**Use ECS Fargate for AWS compute.**

## Alternatives considered

### EKS (rejected)

The portability and ecosystem arguments are real, but the cost is decisive
under the credit constraint. Approximate monthly additions, at standard
published pricing — verify against the AWS calculator before quoting:

| Item | Approx. monthly |
|---|---|
| EKS control plane ($0.10/hr) | ~$73 |
| Two small worker nodes | ~$50-70 |
| Second ALB for cluster ingress | ~$16-20 |
| **Added cost** | **~$140-160** |

Current burn is ~$74/month, so the remaining $103.44 lasts about **six weeks**.
Adding EKS raises the burn to roughly **$215-235/month**, which exhausts the
same credits in about **two weeks** — before the project's evaluation and
hand-over period ends, and in exchange for no capability the workload uses.

Spending the entire remaining budget on a control plane whose features are
unused is not a defensible trade at this scale.

### EC2 with self-managed Kubernetes (rejected)

Removes the control-plane fee but adds the largest operational burden of the
three options: node patching, etcd operation, upgrade orchestration. Strictly
worse than EKS for a single engineer.

### Lambda (rejected)

A reasonable fit for the notification and payment paths, but the frontends and
the booking API are long-lived HTTP services with container images already
built for the Azure side. Splitting runtimes would duplicate the delivery
pipeline for no gain.

## Consequences

### Positive

- No control plane fee, no node management, no cluster upgrade cycle.
- Per-task IAM roles and per-task security groups give an isolation model
  equivalent in practice to Kubernetes RBAC plus NetworkPolicy for this
  workload's threat model.
- Deep AWS integration with Secrets Manager, CloudWatch, Service Connect and
  ALB, with no add-on lifecycle to maintain.
- Credits last through the project's delivery window.
- The container images are identical to those deployed on AKS, so the
  application layer stays portable even though the runtime differs.

### Negative — accepted trade-offs

- **Two deployment flows.** Azure promotes through Argo CD reading Git; AWS
  promotes through the CI pipeline updating the service directly. This is less
  uniform than running Kubernetes on both clouds and is the main cost of this
  decision.
- **No NetworkPolicy, PodDisruptionBudget, operators or service mesh** on the
  AWS side. The Azure side exercises all of these.
- **ECS task definitions are AWS-specific.** Migration away from ECS means
  rewriting the compute layer, though not the application.
- **Single NAT gateway** in the shared VPC is a single point of egress failure.
  One NAT per AZ costs ~$32/month more and was declined under the same credit
  constraint. Documented, not overlooked.

## Revisit triggers

Re-open this decision when any of the following becomes true:

1. The service count grows beyond roughly 15, or more than one team deploys.
2. A requirement appears for operators, CRDs, a service mesh, or multi-tenant
   namespace isolation — for example serving multiple customers on shared
   infrastructure.
3. A single uniform GitOps flow across both clouds becomes a stated
   requirement rather than a preference.
4. Sustained load makes Fargate's per-task premium exceed the cost of EKS plus
   managed nodes with Karpenter.
5. The account moves from promotional credits to a funded budget, removing the
   constraint that drove the cost analysis above.

## Migration path, if triggered

The application layer is already portable. Moving to EKS would require:

| Component | AWS equivalent |
|---|---|
| Helm charts (reuse from `gitops_homeease`) | add `values-aws.yaml` per service |
| Azure Workload Identity | IRSA or EKS Pod Identity |
| Key Vault CSI driver | Secrets Manager CSI driver |
| ACR | ECR (already in place) |
| Azure ingress controller | AWS Load Balancer Controller |
| Argo CD `argocd/azure/` | add `argocd/aws/` app-of-apps |
| CI: ECS service update | CI: bump image tag in Helm values |

Estimated effort: 2-4 days, excluding testing and hardening.
