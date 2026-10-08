# eks-dev - EKS on AWS, managed by the Argo CD on AKS

Kubernetes path for AWS. Same operating model as Azure: managed control plane, Helm charts from
`gitops_homeease`, Argo CD reconciling Git into the cluster, workload identity (IRSA) for secrets.
There is one Argo CD for both clouds: it runs on AKS and manages this cluster as `eks-dev`.
The ECS Fargate path (`../fargate-dev`) is untouched and can be re-applied from the same code.
Decision and cost reasoning: `docs/adr/0002-eks-with-gitops-on-aws.md`.

```
git push (app repo) -> aws-ci.yml: gates, build, sign, push to ECR
                    -> commits image.tag into gitops_homeease charts/<svc>/values-aws-dev.yaml
                    -> Argo CD (hub on AKS) syncs it to eks-dev     <- a deployment is a commit
browser -> CloudFront (HTTPS) -> NLB -> ingress-nginx -> frontend pods -> backend pods -> Atlas (via the NAT's fixed IP)
```

## What Terraform builds here (and what it does not)

| Builds | Does not build (Argo CD / bootstrap owns it) |
|---|---|
| EKS cluster, managed node group, add-ons (vpc-cni with NetworkPolicy, coredns, kube-proxy, EBS CSI, metrics-server) | gp3 default StorageClass, ingress-nginx, Secrets Store CSI driver - `gitops_homeease/scripts/bootstrap-eks.sh`; registration in the AKS Argo CD |
| 3 IRSA roles (app, payment, notification) | The six services, monitoring stack - Argo CD, from Git |
| EKS access entries (who may use kubectl) | Secret **values** - set by hand in Secrets Manager, as today |
| CloudFront x2 (phase 2), apply role, budget | VPC, NAT, ECR, secrets containers - the `dev` stack, reused |

## Order of operations (what you have to do)

1. **Cost check first.** ~$250/month on top of the NAT. Confirm your remaining AWS credits cover the demo window.
2. **Merge the three changes to `main`** (app, gitops, infra). Argo CD reads `main`, CI pushes to `main`, and the apply role only trusts `main`.
3. **First apply, locally** (the CI role does not exist until this runs - chicken and egg):
   ```bash
   cd terraform/aws/environments/eks-dev
   terraform init
   terraform plan -out tfplan        # read it
   terraform apply tfplan            # ~15-20 min (EKS control plane)
   terraform output tf_apply_role_arn
   ```
4. **GitHub settings.**
   - Infra repo, variable `AWS_TF_APPLY_ROLE_ARN` = the output above. Secrets: `GITOPS_REPO_PAT` (read), `GRAFANA_ADMIN_PASSWORD`, `ALERTMANAGER_SMTP_PASSWORD`.
   - App repo, secret `GITOPS_REPO_PAT` (contents: write on the GitOps repo). Variable `AWS_DEPLOY_TARGET` = `eks` (or `both` while ECS still runs; `fargate` restores the old behaviour).
5. **Actions -> `aws-eks-apply` -> action = apply.** Infra (no-op after step 3), then bootstrap (cluster add-ons), then CloudFront. The run summary prints both URLs.
   Then, once, from a machine logged in to the AKS Argo CD: `REGISTER_WITH_HUB=1 scripts/bootstrap-eks.sh`
   in `gitops_homeease` (or `argocd cluster add <eks-context> --name eks-dev` and
   `kubectl apply -f argocd/aws/bootstrap/root-app.yaml` against AKS).
6. **Verify** (checklist below). Only then decommission ECS.
7. **Decommission ECS** - see below.

## Verify

```bash
aws eks update-kubeconfig --name homeease-eks-dev --region ap-south-1
kubectl get nodes                                  # 2 Ready
argocd app list | grep aws                         # on the AKS hub: all Synced / Healthy
kubectl get pods -n homeease-dev                   # 6 services Running
kubectl get secret backend-secrets -n homeease-dev # exists => IRSA + Secrets Manager + CSI sync work
kubectl get svc -n ingress-nginx                   # two NLB hostnames
curl -sI "$(terraform output -raw app_url)"        # 200
```
Then a real booking end to end, and **sign in from two different networks** to confirm the rate-limit
buckets are separate (that is the check for `TRUST_PROXY_HOPS: "3"` in `values-aws-dev.yaml`).
Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`.

## Decommission ECS (after EKS is verified)

Code stays; only the running resources go. Re-apply `fargate-dev` any time to bring it back.

**Option A - GitHub Actions.** Set `create_fargate_teardown_role = true` in `terraform.tfvars`, apply this stack, set the
repo variable `AWS_FARGATE_TEARDOWN_ROLE_ARN` (output `fargate_teardown_role_arn`), run `aws-fargate-destroy`
(type `destroy-fargate-dev`). Afterwards set the flag back to `false` and apply: that role is broad (PowerUserAccess).

**Option B - locally, your own credentials (no broad role created):**
```bash
cd terraform/aws/environments/fargate-dev
terraform init
# Keep CloudTrail, GuardDuty and the audit bucket (a non-empty bucket would also block the destroy):
for a in aws_cloudtrail.this aws_guardduty_detector.this aws_s3_bucket_policy.audit_logs \
         aws_s3_bucket_lifecycle_configuration.audit_logs aws_s3_bucket_server_side_encryption_configuration.audit_logs \
         aws_s3_bucket_public_access_block.audit_logs aws_s3_bucket.audit_logs; do
  terraform state list | grep -qx "$a" && terraform state rm "$a"
done
terraform plan -destroy -out destroy.tfplan
terraform apply destroy.tfplan
```
The audit baseline is then running but unmanaged; importing it into this stack is a follow-up.

## Known limits

- Public Kubernetes API endpoint (`0.0.0.0/0`, authentication required). Narrow `public_access_cidrs`.
- One NAT gateway (shared dev stack), single region. Nodes egress through it, so the Atlas allowlist works unchanged.
- No CloudWatch dashboards/alarms on this path: Prometheus + Alertmanager (same as Azure) replace them. The Azure DORA exporter is not deployed.
- `kubernetes_version = null` takes EKS's current default; pin it after the first apply.
- Load balancers use the in-tree NLB annotations. The AWS Load Balancer Controller is the stricter long-term option.
