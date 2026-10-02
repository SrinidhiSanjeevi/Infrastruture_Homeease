# fargate-dev

The live AWS compute path — 5 HomeEase services on ECS Fargate, behind
one ALB, sharing `environments/dev`'s VPC/ECR/Secrets Manager. Written,
**not applied** — no AWS credentials or account exist in the environment
this was built in to run `terraform apply` against. See the root
README's "Should `terraform apply` be automated?" section for the CI
wiring this environment is designed to slot into once someone does
apply it.

## Why Fargate, not the EKS path in `_reference-eks/`

EKS's own header comment (now in `_reference-eks/environments/dev/
main.tf.orig`) already priced it: ~$135/month baseline (EKS control
plane + NAT Gateway + one node) before any autoscaling. Fargate has no
per-cluster control plane fee — see the cost estimate in
`main.tf`'s header comment (~$40-60/month all-in at default sizing, on
top of `environments/dev`'s ~$32/month VPC/NAT, which is paid either
way).

## What's here vs. what it builds on

| Owned here | Owned by `environments/dev` (read via `terraform_remote_state`) |
|---|---|
| ECS cluster + Service Connect namespace | VPC, public/private subnets |
| ALB, 2 target groups, 2 listeners (80 → frontend, 8081 → admin-frontend, same ports `docker-compose.yml` already uses) | ECR repositories |
| 5 ECS services + task definitions | Secrets Manager containers (`backend`, `admin-backend`, `payment-service`) |
| 3 task execution roles (web / backend / payment — mirrors the Workload Identity / IRSA split on the other two clouds) | GitHub OIDC provider |
| Security groups per service, ingress scoped to match each service's `NetworkPolicy` in `gitops_homeease` exactly | |
| This stack's own `tf-apply` IAM role | |

## Ingress topology (mirrors `gitops_homeease`'s NetworkPolicies)

```
ALB :80    -> frontend
ALB :8081  -> admin-frontend
frontend, admin-frontend -> backend            (proxied /api/ calls)
admin-frontend           -> admin-backend
backend                  -> payment-service    (the ONLY caller, tightest SG in the stack)
```

## The "GitOps" part — how an image gets from ECR onto a running task

There is no Argo CD equivalent here on purpose: Argo CD is a Kubernetes
controller, and Fargate isn't Kubernetes — bolting a K8s-shaped
reconciler onto ECS would be the "add a tool without a justified
benefit" mistake this project has consistently avoided elsewhere. The
mechanism instead:

1. `app_Homeease`'s `aws-ci.yml` builds, scans, SBOMs, signs, and pushes
   a service's image to ECR (already true today).
2. A new step clones this repo and rewrites `image_tags.<service>` in
   `image-tags.auto.tfvars`, commits, and pushes to `main` — the exact
   mechanism `azure-pipelines.yml`'s Promote stage already uses against
   `gitops_homeease`.
3. A new GitHub Actions workflow in **this** repo, triggered on a push
   to `main` that touches this file, runs `terraform plan` then
   `terraform apply` for `fargate-dev` — gated behind a GitHub
   Environment (`aws-fargate-dev`) the same way `prod`'s Terraform plan
   already requires reviewer approval.

`.tfvars` committed to git IS the GitOps state for this stack, the same
way `values-azure-dev.yaml` is for the Helm/Argo CD path — just without
a cluster-side controller pulling it, since apply already runs from CI.

## First apply (by a human, once)

```bash
cd terraform/aws/environments/fargate-dev
cp terraform.tfvars.example terraform.tfvars   # fill in registry_state_bucket, budget_contact_emails
terraform init
terraform plan
terraform apply
terraform output tf_apply_role_arn              # paste into this repo's "aws-fargate-dev" GitHub Environment
terraform output frontend_url admin_frontend_url # what to open in a browser
```

Real images have to exist in ECR first — `image-tags.auto.tfvars`
ships with `REPLACE_ME` placeholders, which will not resolve to a
pullable image. Run `app_Homeease`'s `aws-ci.yml` (or push a real tag
into this file by hand) before the first apply, or the services will
sit in a perpetual failed-to-pull state.

## Production-readiness additions (manual apply, no Terraform pipeline)

| Added | Where |
|---|---|
| Deployment circuit breaker + automatic rollback, ALB health-check grace period | `modules/ecs-service` |
| Container Insights (`container_insights = true` by default) | `modules/ecs-cluster` |
| CloudWatch alarms: CPU/memory per service, unhealthy hosts and 5xx per target group, all notifying an SNS topic (email) | `modules/ecs-service`, `modules/alb` |
| Optional HTTPS: set `certificate_arn` to get a 443 listener, with :80 redirecting to it | `modules/alb` |
| tf-apply role permissions for the above | `main.tf` |

### Steps

1. **Fix the secrets first** (the real cause of the failing services):
   - `backend` and `admin-backend` log `bad auth : authentication failed`, so the `mongo-uri` secret holds wrong Mongo credentials. Put a valid URI in `homeease/dev/backend/mongo-uri` and `homeease/dev/admin-backend/mongo-uri`.
   - `payment-service` logs `Missing required environment variable: MONGO_URI`. The live task definition lacks the secret, and this change adds it. Set a value in `homeease/dev/payment-service/mongo-uri` too.
   - `frontend` and `admin-frontend` crash with `host not found in upstream backend:5000`. They recover on their own once the backends are healthy.
2. `terraform plan` then `terraform apply` in this directory.
3. Confirm the SNS email subscription (link emailed to `budget_contact_emails`).
4. Force a fresh start after fixing secrets:
   `aws ecs update-service --cluster homeease-dev --service homeease-dev-<name> --force-new-deployment`
   (backend and admin-backend first, then the two frontends).
5. Open `terraform output frontend_url` and `admin_frontend_url`.
6. HTTPS later: request an ACM certificate for your domain, set `certificate_arn` in `terraform.tfvars`, apply, and point DNS at `alb_dns_name`.

## Azure Blob images + MongoDB Atlas

Both backends read images from the Azure Storage account `sthomeeaseimgayhiue` (containers `service-images`, `professional-images`). AWS has no Azure Workload Identity, so they use the storage **account key** path already in `services/blobStorage.js`. The account name is a plain env var and the key comes from Secrets Manager.

**Order matters** (fargate-dev reads the new secrets from the dev stack):

1. `cd ../dev && terraform apply` creates the empty secrets `homeease/dev/backend/azure-storage-account-key` and `homeease/dev/admin-backend/azure-storage-account-key`.
2. Set their values, using the same key in both:
   ```bash
   KEY=$(az storage account keys list -n sthomeeaseimgayhiue --query '[0].value' -o tsv)
   for s in backend admin-backend; do
     aws secretsmanager put-secret-value --region ap-south-1 \
       --secret-id homeease/dev/$s/azure-storage-account-key --secret-string "$KEY"
   done
   ```
3. `cd ../fargate-dev && terraform apply`.

**Atlas:** `mongo-uri` for backend, admin-backend and payment-service must be the Atlas `mongodb+srv://user:pass@cluster/db` string. Atlas must also allow the AWS NAT Gateway's public IP (Tasks leave the VPC through it): Atlas, Network Access, Add IP Address, `35.154.153.215`. Check it with `aws ec2 describe-nat-gateways`. URL-encode special characters in the password (`@` becomes `%40`).
