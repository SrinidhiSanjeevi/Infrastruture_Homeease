# Infrastructure_Homeease

Terraform IaC for HomeEase's cloud infrastructure. Two independent cloud
stacks live here side by side:

- **`terraform/azure/`** — the ONLY infrastructure actually provisioned
  today. Backs `aks-homeease-dev`, the one live cluster `gitops_homeease`
  deploys to.
- **`terraform/aws/`** — split by compute path. `environments/dev/`
  (ECR + CI OIDC + VPC + Secrets Manager) is compute-agnostic and
  written to be applied. On top of it, **`environments/fargate-dev/`**
  is the live compute path — 5 services on ECS Fargate behind one ALB,
  written but not yet applied (see its own README for why and the cost
  estimate). `_reference-eks/` holds the Kubernetes-on-AWS path that
  preceded Fargate — parked, not applied, kept for reference (its own
  README explains the ~$135/month reason it moved here).

Companion repos: `app_Homeease` (application code + CI, pushes images to
ACR/ECR) and `gitops_homeease` (Helm charts + Argo CD, consumes this
repo's outputs — see "Hand-off to GitOps" below).

## Is this "complete" IaC?

Two different questions, two different answers:

**Is every resource defined as code, with nothing created by hand in a
portal?** Yes, for Azure. Resource Group, VNet/Subnets/NSG, ACR, AKS
(CNI Overlay, Workload Identity, Key Vault CSI add-on, AcrPull role),
Key Vault, the User-Assigned Managed Identity + Federated Credential,
and the Key Vault secret declarations are all Terraform resources under
`terraform/azure/modules/`. Nothing here needs Azure Portal clicking.

**Does a pipeline actually apply that code to real infrastructure?**
No — and that's deliberate, not a gap. `.github/workflows/terraform.yml`
and `terraform-aws.yml` are **plan-only by design** (see each file's own
header comment): they run `checkov`, `terraform fmt`, `validate`, and
`plan` on every PR and push, matrixed over `dev`/`staging`/`prod`, each
with its own least-privilege OIDC identity and its own GitHub
Environment (so `prod`'s plan can require reviewer approval before its
OIDC token is even minted). `terraform apply` is a human running it
locally, on purpose — see "What's still genuinely manual" below for why
that boundary hasn't moved yet, and "Should apply be automated?" for the
actual trade-off if you want to close it.

## What's still genuinely manual

Three concrete things, not a vague caveat:

1. **`terraform apply` itself.** CI never runs it (see above). A human
   runs the cheat sheet below from their own machine, against their own
   `az login` session.
2. **The Azure DevOps service connection.** `terraform/azure/environments/
   dev/ci.tf` provisions the Azure AD app registration + federated
   credential for ADO's Workload Identity federation, but creating the
   actual ADO **service connection** that uses it is a manual step in
   Azure DevOps' UI (Project Settings → Service Connections → New →
   Azure Resource Manager → Workload Identity federation) — the
   `azuredevops` Terraform provider can't create this side of a WIF
   service connection. `ci.tf`'s own header comment walks through the
   exact order (pick the name first, apply, then create the connection
   with that exact name — a mismatch fails with an opaque
   `AADSTS700213`).
3. **`ado_organization_id`.** Currently `enable_azure_devops = false` in
   `ci.tf` because this value is still the placeholder
   `"REPLACE-AFTER-ADO-CHECK"` — fetching the real GUID needs an
   authenticated browser session against `https://dev.azure.com/<org>/
   _apis/connectionData`, not something a CI job can curl anonymously.
   Flip the flag once it's real.

## Should `terraform apply` be automated?

Worth deciding deliberately, not defaulting either way:

- **Extend the existing workflow** (recommended starting point): add an
  `apply` job to `terraform.yml`/`terraform-aws.yml` that consumes the
  plan artifact and runs behind the *same* per-environment GitHub
  Environment approval the plan job already has wired up for `prod`.
  Smallest change — no new tool, no new server, reuses the
  least-privilege OIDC identities and environment-approval gating that
  already exist. This is the same pattern `app_Homeease`'s
  `azure-pipelines.yml` already uses for its own approval-gated PROD
  promotion.
- **Atlantis** (or similar PR-ops tooling) gives a different, genuinely
  nice workflow — plan output as a PR comment, `atlantis apply` to
  approve inline, built-in state locking across concurrent PRs. But it
  needs a persistently-running server (self-hosted or SaaS), webhook
  wiring, and its own credential/locking model — real new operational
  surface for what GitHub Environments + required reviewers already get
  most of the way to.

Given this project's existing bias toward the smallest sensible change
(see `gitops_homeease`'s README for the same judgment applied to
Kyverno/KEDA/zone-spreading), extending the existing workflow is the
more consistent next step. Atlantis is a legitimate alternative if the
PR-comment UX specifically matters for the team, not because the
current setup is missing something it needs.

**`terraform-aws-fargate-apply.yml` is that first concrete instance** —
a real plan-then-apply pipeline, scoped to exactly one environment
(`fargate-dev`), gated behind a GitHub Environment's required
reviewers, applying the exact plan artifact that was reviewed rather
than a fresh one. `terraform.yml`/`terraform-aws.yml` themselves are
untouched — this is a deliberate, separate exception, not a silent
policy change for `dev`/`staging`/`prod`.

## Directory structure

```
terraform/
  azure/
    bootstrap/        Stage 0, run once: Storage Account + Blob container for
                       remote state (backend "local" the first time, never again)
    modules/           resource-group, networking, acr, aks, keyvault,
                       workload-identity, secrets, ci-identity
    environments/
      dev/             LIVE — backs aks-homeease-dev. Own backend.tf (remote
                       state key), own ci.tf (least-privilege CI identity),
                       real terraform.tfvars (gitignored, local-only)
      staging/         defined, not applied — no staging cluster exists
      prod/            defined, not applied — no prod cluster exists

  aws/
    bootstrap/         Stage 0, same idea as azure/bootstrap — S3 bucket + lock
    modules/            ecr, networking, secrets, ci-oidc, tf-apply-role (compute-
                       agnostic, shared) + ecs-cluster, ecs-service, alb (Fargate)
    environments/
      dev/              LIVE — ECR, VPC, GitHub OIDC, Secrets Manager containers.
                       No compute. Four independent configs (not one parameterised
                       by var.environment like Azure) — dev alone owns the
                       account-wide singletons (see environments/dev/main.tf).
      fargate-dev/      LIVE compute path — 5 services on ECS Fargate + ALB, built
                       on dev's outputs via terraform_remote_state. Written, not
                       yet applied — see its own README.
      staging/, prod/   defined, not applied — compute-agnostic scaffolding only
    _reference-eks/     PARKED — the Kubernetes-on-AWS path Fargate replaced.
                       modules/{eks,irsa} + a snapshot of what environments/dev/
                       looked like with them wired in. See its own README.

  persistent/
    azure-storage/     DNS / storage that must outlive any environment teardown
    aws-route53/        same idea, AWS side

.github/workflows/
  terraform.yml                    Azure: checkov -> fmt/validate/plan, matrixed dev/staging/prod
  terraform-aws.yml                AWS: same shape, GitHub OIDC -> IAM role per environment
  terraform-aws-fargate-apply.yml  AWS fargate-dev ONLY: plan -> environment approval -> apply
                                   — the one exception to "apply is manual", see above
  terraform-drift.yml               Azure dev ONLY, scheduled: read-only terraform plan
                                   -detailed-exitcode against live infra. Opens/updates/closes
                                   one GitHub issue on drift — never applies or destroys.
```

## Drift detection (Azure dev)

`terraform.yml` proves a *proposed* change is safe. `terraform-drift.yml`
proves infrastructure that was already applied still matches what
Terraform thinks exists — the two drift the moment anyone changes
something by hand in the Portal, runs an ad-hoc `az` command, or an
Azure-managed feature changes a tracked value. Runs daily, read-only
(`terraform plan` only — never `apply`/`destroy`, deliberately: a human
decides whether drift is a legitimate manual fix to reconcile back into
config, or a process bypass worth investigating). Needs the
`DEV_TFVARS_CONTENT` repo secret set to the contents of the real
`terraform.tfvars` — stored as a secret purely because it's
environment-specific, not because it's sensitive; every value in it
(region, node count, VM size, CIDRs, an Azure AD object ID) is
non-credential config, and real secrets here are Key Vault-managed, never
Terraform variables. dev only — staging/prod have never been applied, so
"drift" against them is meaningless (everything would show as "to be
created", not drift).

## Hand-off to GitOps

Terraform outputs feed `gitops_homeease`'s `values-azure-dev.yaml` files
directly (copied in by hand today, not templated):

| Terraform output | Consumed as |
|---|---|
| `workload_identity_app_client_id` | `workloadIdentity.clientId` in each service's `values-azure-dev.yaml` |
| `key_vault_name` | `keyVault.name` |
| `acr_login_server` | `image.repository` prefix in `charts/*/values.yaml` |
| `resource_group_name` | Key Vault CSI tenant configuration |

## IaC scanning

`checkov` runs repo-wide in both workflows, gating the build
(`soft-fail: false`). Two Azure findings are explicitly skipped, with
the trade-off documented rather than silently suppressed:
`CKV_AZURE_137` (ACR public network access) and `CKV_AZURE_109` (Key
Vault public network access) — both are the same root cause: Basic-tier
SKUs on a trial subscription can't have a Private Endpoint. Fix is
Premium SKU + Private Endpoint; tracked as future work, not ignored.

## Terraform commands cheat sheet

```bash
# 1. Login
az login --tenant <TENANT_ID>
az account set --subscription <SUBSCRIPTION_ID>

# 2. Navigate to the environment
cd terraform/azure/environments/dev

# 3. Init, validate, plan, apply
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# 4. Inspect
terraform output
terraform state list
terraform state show module.aks.azurerm_kubernetes_cluster.this
```
