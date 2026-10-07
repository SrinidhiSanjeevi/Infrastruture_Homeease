> **Update 2026-10-07:** the `eks` and `irsa` modules were promoted to `terraform/aws/modules/` and are used by
> `environments/eks-dev` (see `docs/adr/0002-eks-with-gitops-on-aws.md`). This folder is kept as history.

# Parked — EKS (Kubernetes on AWS) reference

**Not applied. Not planned by any CI workflow.** This is the Kubernetes
path for AWS, kept as a working reference next to the Fargate path that
actually replaced it (`terraform/aws/environments/fargate-dev/`).

## Why this exists instead of being deleted

`terraform/aws/environments/dev/main.tf` used to instantiate `module.eks`
and `module.irsa` directly — `environments/dev/main.tf.orig` in this
folder is the exact file as it stood before that changed, so the full
original picture (VPC + EKS + IRSA + ECR + CI, one environment) is still
readable in one place. The live `environments/dev/main.tf` now stops at
ECR + CI identity + Secrets Manager containers — the account-wide,
compute-agnostic pieces both paths share.

**The real reason EKS moved here rather than being applied:** its own
header comment already priced it out — EKS control plane is ~$73/month
flat (no free tier), plus ~$32/month for the NAT Gateway, plus ~$30/month
for one `t3.medium` node ≈ **$135/month baseline before any autoscaling**.
Fargate gets the same 5-service app running with no per-cluster control
plane fee at all — see the root README's cost comparison.

## What's here

```
modules/
  eks/     EKS cluster module — CNI, node group, OIDC issuer for IRSA
  irsa/    IAM Roles for Service Accounts — payment-service's pod-level
           AWS identity, federated via the EKS OIDC issuer
environments/
  dev/
    main.tf.orig        environments/dev/main.tf as it stood with EKS
                         wired in — not meant to `terraform init` on
                         its own (its ecr/ci_oidc/budget resources
                         would collide with the live dev environment's
                         state if you tried)
    variables.tf.orig   the matching variables.tf
```

## To re-enable EKS instead of Fargate

1. `git mv terraform/aws/_reference-eks/modules/eks terraform/aws/modules/eks`
   (same for `irsa`).
2. Add the `module "eks"` and `module "irsa_payment"` blocks back into
   `terraform/aws/environments/dev/main.tf` (copy from `environments/
   dev/main.tf.orig` in this folder), and the matching variables from
   `variables.tf.orig`.
3. Point `module.ecr`'s `pull_principal_arns` back at
   `module.eks.node_role_arn` (Fargate's version grants ECR pull to a
   task execution role instead — see `environments/fargate-dev/main.tf`
   for that mechanism, which would need removing or the two would both
   try to manage the same repository policy).
4. Raise `monthly_budget_amount` before applying — see the cost note
   above, it will alert immediately at the historical default.
5. In `gitops_homeease`, `argocd/_aws-disabled/` is the matching parked
   ArgoCD config for this cluster — see its own README for what moving
   it back to `argocd/aws/` requires (new `values-aws-dev.yaml` per
   chart, IRSA in place of Workload Identity, EKS cluster reachable).
