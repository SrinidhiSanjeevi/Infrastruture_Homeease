# HomeEase infrastructure: how it is run

## Delivery flow

```
PR / push to main
  Validate: gitleaks -> fmt -> validate (4 roots) -> tflint -> infracost -> checkov
  Plan dev | Plan staging | Plan prod     (read-only identity, saved plan = artifact)
  Apply dev      <- approval + exclusive lock on Environment homeease-dev (real apply)
  Apply staging  <- demo: prints a message, nothing deployed
  Apply prod     <- demo: prints a message, nothing deployed
Nightly: terraform-drift.yml  -> plan -detailed-exitcode, fails on drift
```

Why this is safe: the plan that was reviewed is the artifact that is applied (same commit,
same files), no secrets exist in the pipeline (OIDC federation), and the apply identity
can only hand out five named roles (ABAC condition in bootstrap).

## State locking

- State lives in Azure Blob (one key per environment, versioning + 30-day soft delete).
  The azurerm backend takes a blob **lease** on every plan/apply, so two writers can never
  run on one environment.
- Pipeline layers on top: `lockBehavior: sequential` (queued runs wait instead of failing),
  `-lock-timeout=10m`, and an Exclusive Lock check on the Environment.
- Stuck lock (agent killed mid-apply): `terraform force-unlock <LOCK_ID>` from the dev
  directory, or `az storage blob lease break` on the state blob. Check no run is active first.
- Corrupt/deleted state: restore the previous blob version (Portal > container > blob > Versions).

### Atlantis / Terragrunt: what we use instead

| Team tool | What it gives | HomeEase equivalent |
|---|---|---|
| Atlantis | plan on PR, apply by approval, per-dir locks | Azure DevOps PR trigger + saved plan + Environment approval + blob lease + `lockBehavior` |
| Terragrunt | DRY config, env wiring, dependency order | one root per environment sharing `modules/`, pinned versions, one tfvars per env |

Talking point: the same controls with zero extra servers or licences, and the apply uses an
immutable saved plan, which Atlantis only does when configured to.
Adopt Atlantis/Terragrunt when there are 10+ roots or many teams.

## One-time setup in the Azure DevOps UI

1. Environments: create `homeease-dev`, `homeease-staging`, `homeease-prod`.
   Add Approvals and (dev) Exclusive Lock checks. Prod: 2 approvers.
2. Library > Secure files: `dev.tfvars` (real values, incl. the hardening variables).
3. Pipeline variable (secret): `INFRACOST_API_KEY` (free key: `infracost auth login`).
4. New pipeline from `pipelines/terraform-drift.yml`. Project settings > Notifications: mail on failure.
5. Read-only plan identity: create service connection `azure-homeease-plan` (workload identity
   federation). Put its service principal object ID in bootstrap as `plan_principal_object_id`
   and apply bootstrap. Then set `PLAN_CONNECTION: azure-homeease-plan` and `PLAN_LOCK: "false"`
   in both pipeline files.
6. Branch policy on `main`: PR required, build validation = this pipeline, 1 reviewer.

## One-time commands (laptop, manual roots)

```
cd terraform/azure/bootstrap
terraform init -migrate-state -force-copy      # local state -> blob (backend key bootstrap.terraform.tfstate)
terraform apply                                 # soft delete + policy + plan roles
```

## Hardening switches (environments/dev, via dev.tfvars)

| Variable | Effect |
|---|---|
| `api_server_authorized_ip_ranges` | only these IPs reach the Kubernetes API |
| `aks_admin_group_object_ids` + `aks_local_account_disabled` | Entra ID sign-in, static admin kubeconfig off |
| `keyvault_restrict_network` + `keyvault_allowed_ip_ranges` | Key Vault firewall: deny, allow AKS subnet + admin IP |
| `enable_tag_policy` | Azure Policy denies resources without project/environment/owner tags |

Get your IP: `curl -s ifconfig.me`. Group: `az ad group create --display-name homeease-aks-admins --mail-nickname homeease-aks-admins`.
If you lock yourself out of the API server, change the variable and re-apply (ARM, not kubectl).

## Alerts

`modules/alerts`: e-mail action group + AKS node CPU > 80% and memory > 80% (15 min).
Budget alerts at 50/80/100% already exist. Dev is demo-sized; staging/prod would add the same module.

## Runbook

| Situation | Action |
|---|---|
| Nightly drift run red | Open the plan. Portal edit is right -> copy it into code; wrong -> re-apply to revert |
| Apply failed half-way | Re-run: plan again, apply the new plan. Never apply an old artifact |
| Lock stuck | See *State locking* |
| Budget alert | Scale AKS to 0 / run `terraform-destroy.yml` (type `destroy-dev`) |
| Rebuild dev after destroy | Run main pipeline; `dev-identity` and `bootstrap` survive a dev destroy |
| Lost a secret | Key Vault secrets are manual (modules/keyvault/SECRETS.md); purge protection is on |

## Known gaps (accepted for demo)

- Staging/prod are plan-only; prod `enable_delete_lock = true` is set in code, dev leaves it off so destroy works.
- `ado_organization_id` is still a placeholder; only needed to enable the ADO federated credential in `dev-identity`.
- No DR/backups beyond state versioning: nothing stateful runs in the cluster yet.
