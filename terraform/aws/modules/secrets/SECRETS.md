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

Names here are what the `secretProviderClass.objects[].awsSecret` entries
in `gitops_homeease`'s `charts/<service>/values-aws-dev.yaml` reference.
The containers are created in `environments/dev/main.tf`. Keep both sides
in sync by hand, since nothing enforces this automatically
(deliberately: see above for why nothing should).

All names are `homeease/dev/<service>/<suffix>`:

| Service | Secret suffixes |
|---|---|
| backend | `mongo-uri`, `jwt-secret`, `email-user`, `email-pass`, `azure-storage-account-key` |
| admin-backend | `mongo-uri`, `jwt-secret`, `azure-storage-account-key` |
| payment-service | `mongo-uri`, `razorpay-key-id`, `razorpay-key-secret`, `razorpay-webhook-secret` |
| notification-service | `mongo-uri`, `email-user`, `email-pass` |

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
