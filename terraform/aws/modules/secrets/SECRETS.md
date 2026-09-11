# How application secrets actually get into Secrets Manager

Same rule as `terraform/azure/modules/keyvault/SECRETS.md`: Terraform
manages the secret **container** (`main.tf` in this module) and, via
`modules/irsa`, **who can read it**. Terraform never manages the secret
**value** — there is no `aws_secretsmanager_secret_version` resource
anywhere in this module. Any Terraform resource or data block that
touches a real secret value writes that value into the Terraform state
file in plaintext; `sensitive = true` only hides it from console
output, not from state.

## Setting a value, one time, by hand

```bash
aws secretsmanager put-secret-value \
  --secret-id homeease/dev/payment-service/razorpay-key-id \
  --secret-string "<the real value>" \
  --region ap-south-1
```

Whoever runs this needs `secretsmanager:PutSecretValue` on the secret —
narrower than the read-only `secretsmanager:GetSecretValue` /
`DescribeSecret` the workload's IRSA role gets from `modules/irsa`. Grant
it to a human/admin principal explicitly; the node role and the
workload's own IRSA role never get write access.

## Naming convention

Names here are what `gitops_homeease`'s AWS `SecretProviderClass`
resources reference by `objectName` (see
`apps/payment-service/overlays/aws/dev/secretproviderclass.yaml`) — keep
both sides in sync by hand, since nothing enforces this automatically
(deliberately: see above for why nothing should).

| Secrets Manager secret name                              | Consumed by     | Env var it becomes        |
| ---------------------------------------------------------| ---------------- | -------------------------- |
| `homeease/dev/payment-service/razorpay-key-id`            | payment-service | `RAZORPAY_KEY_ID`          |
| `homeease/dev/payment-service/razorpay-key-secret`        | payment-service | `RAZORPAY_KEY_SECRET`      |
| `homeease/dev/payment-service/razorpay-webhook-secret`    | payment-service | `RAZORPAY_WEBHOOK_SECRET`  |

## Rotation

Same command, new `--secret-string`. Secrets Manager versions secrets
automatically (`AWSCURRENT`/`AWSPREVIOUS` stages) — nothing is deleted
outright. Unlike Key Vault's CSI driver, the Secrets Store CSI driver's
AWS provider does not poll for changes by default; a rotated value
needs `kubectl rollout restart deployment/payment-service` (or a
scheduled sync + reloader) to actually reach the running pod, same as
the Azure side for any service that only reads its env vars at startup.

## What NOT to do

- Don't put a real value in any `.tfvars` file, even a gitignored one —
  the moment it's ever passed as `TF_VAR_*`, Terraform state has it.
- Don't pass secret values through CI pipeline variables "just to get
  them into Secrets Manager." If a value already lives there, Terraform
  and CI have no reason to ever see it again.
- Don't add an `aws_secretsmanager_secret_version` resource to this
  module. If a future need arises to track secret *existence* as code
  (e.g. for compliance), use `data "aws_secretsmanager_secret"` reading
  only `.arn`/`.id` and never `.secret_string` — but confirm first that
  the requirement can't be met more simply by this file.
