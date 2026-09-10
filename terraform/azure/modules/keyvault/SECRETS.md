# How application secrets actually get into Key Vault

Terraform manages the Key Vault **container** (`main.tf` in this
module) and **who can read it** (RBAC role assignments in
`modules/workload-identity`). Terraform does not manage, and must
never manage, the secret **values** inside it. See the deleted
`modules/secrets` module for why: any Terraform `resource` or `data`
block that touches a real secret value writes that value into the
Terraform state file in plaintext — `sensitive = true` only hides it
from console output, not from state.

## Setting a value, one time, by hand

```bash
az keyvault secret set \
  --vault-name kv-homeease-dev-hs01 \
  --name mongo-uri \
  --value "<the real connection string>"
```

Whoever runs this needs `Key Vault Secrets Officer` on the vault —
that's the role `modules/workload-identity` already grants to
`var.admin_object_id`. The AKS workload identity only ever gets
`Key Vault Secrets User` (read-only) — it cannot set or rotate a
value even if compromised.

## Naming convention

Names here are what `gitops_homeease`'s `SecretProviderClass`
resources reference by `objectName` — keep both sides in sync by
hand, since nothing enforces this automatically (deliberately: see
above for why nothing should).

| Key Vault secret name | Consumed by | Env var it becomes |
|---|---|---|
| `mongo-uri` | backend, admin-backend | `MONGO_URI` |
| `jwt-secret` | backend, admin-backend | `JWT_SECRET` |
| `email-user` | backend | `EMAIL_USER` |
| `email-pass` | backend | `EMAIL_PASS` |
| `razorpay-key-id` | payment-service | `RAZORPAY_KEY_ID` |
| `razorpay-key-secret` | payment-service | `RAZORPAY_KEY_SECRET` |
| `razorpay-webhook-secret` | payment-service | `RAZORPAY_WEBHOOK_SECRET` |

## Rotation

Same command, new `--value`. Key Vault versions secrets
automatically — the old version isn't deleted, just superseded. The
Secrets Store CSI driver's `secret_rotation_enabled` (already set in
`modules/aks`) polls Key Vault and updates the mounted file /
synced Kubernetes Secret without a pod restart on its own polling
interval; an app that only reads an env var at startup (all four
HomeEase services do) still needs a rolling restart to pick up a
rotated value — `kubectl rollout restart deployment/<service>` after
rotating, or wire a reloader (stakater/Reloader) later if this needs
to be automatic.

## What NOT to do

- Don't put a real value in any `.tfvars` file, even one that's
  gitignored — the moment it's ever passed as `TF_VAR_*`, Terraform
  state has it.
- Don't pass secret values through CI pipeline variables "just to
  get them into Key Vault." If a value already lives in Key Vault,
  Terraform/CI have no reason to ever see it again.
- Don't recreate `modules/secrets`. If a future need arises to track
  secret *existence* as code (e.g. for compliance), do it with
  `data "azurerm_key_vault_secret"` reading only `.id`/`.version`
  metadata and never referencing `.value` — but confirm first that
  the requirement can't be met more simply by this file.
