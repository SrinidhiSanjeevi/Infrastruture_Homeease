# HomeEase Azure Modules: Evaluation Walkthrough

Script for the video. Each section answers: **what it creates, how it's built, why, and how it's secured.**

## 0. Opening (30 seconds)

"HomeEase's Azure infrastructure is 100% Terraform. There are seven reusable modules under `terraform/azure/modules/`. Three environments (dev, staging, prod) each call the same modules with their own values, so the three environments can't drift apart in design. Every module follows three rules:
1. **No passwords or keys.** Identity is handled with OIDC and managed identities.
2. **Least privilege.** Each identity gets one role on one resource.
3. **Auditable.** Every sensitive action is logged, and prod is locked against deletion."

```
GitHub/ADO ──OIDC──► ci-identity ──AcrPush──► ACR ◄──AcrPull── AKS (kubelet)
                                                               │ OIDC issuer
Pod ServiceAccount ──federated credential──► workload-identity ──Secrets User──► Key Vault
                      everything sits in one Resource Group / VNet; logs → Log Analytics
```

## 1. resource-group
- **What:** `rg-homeease-<env>`, one per environment.
- **Why:** The resource group is the blast-radius boundary. The CI identity is scoped to this group only, budgets attach to it, and deleting an environment means deleting one group. Tags (`project`, `environment`, `managed_by`, `owner`) support cost tracking and ownership.

## 2. networking
- **What:** a VNet with two subnets (AKS nodes and a reserved private-endpoint subnet), each with its own NSG.
- **Why:** Separate subnets let each tier have its own firewall rules. The private-endpoint subnet is already in place, so moving ACR and Key Vault to private access later needs no network redesign.
- **Security:** NSGs are default-deny inbound, and only 80/443 and the load-balancer probe are opened.
- **Honest trade-off:** the NodePort range is open to the Internet. It is required for the current ingress path, and it is the first thing to tighten once traffic goes through a WAF or Application Gateway.

## 3. acr (container registry)
- **What:** one registry per environment that stores that environment's images.
- **How it's secured:**
  - `admin_enabled = false`, so there is no shared username/password.
  - `anonymous_pull_enabled = false`, so every pull needs authentication.
  - **Push:** only the CI identity, through OIDC federated credentials, with the `AcrPush` role. No secret exists to leak.
  - **Pull:** only the AKS kubelet identity, with `AcrPull`. It cannot push.
  - **Audit:** every login, push and pull goes to Log Analytics.
  - **Prod:** `CanNotDelete` lock.
- **Accuracy note for the video:** OIDC is what secures *pushes from the pipeline*. What stops unauthorised manual change is **RBAC plus the delete lock**. Don't claim that OIDC alone makes it unchangeable.
- **Known trade-off:** the public endpoint stays on because the CI agents are outside the VNet. The fix is Premium SKU plus a Private Endpoint, and it's documented as future work.

## 4. aks (Kubernetes)
- **What:** an autoscaling cluster (1–3 nodes) on Azure CNI Overlay, with Azure network policy.
- **How it's secured:**
  - **Workload Identity + OIDC issuer:** pods get Azure tokens without stored credentials.
  - **Managed identity**, with no service-principal secret.
  - **Key Vault CSI driver:** secrets are mounted and rotated every 2 minutes, never baked into images.
  - **Kubernetes RBAC on.**
  - **Auto-upgrade (`patch`) plus NodeImage OS upgrades:** security patches apply themselves.
  - **Image cleaner:** removes stale vulnerable images.
  - **Azure Policy add-on:** enforces pod-security baselines.
  - **Audit logs** (`kube-audit-admin`, `guard`) and Container Insights go to Log Analytics.
- **Switches already built, off by default so nothing breaks:** Entra ID login with Azure RBAC, disabling the static admin kubeconfig, and API-server IP allow-listing. Turn them on by setting `admin_group_object_ids`, `local_account_disabled` and `api_server_authorized_ip_ranges`.

## 5. keyvault
- **What:** one vault per environment for application secrets. `SECRETS.md` documents each secret.
- **How it's secured:**
  - **Azure RBAC, not access policies.** Access is auditable through role assignments.
  - **Purge protection on, soft delete on.** A deleted secret can be recovered and cannot be permanently destroyed early.
  - **Audit log** of every read and write.
  - **Firewall option** (`network_acls`) is ready.
  - **Prod:** delete lock.

## 6. workload-identity
- **What:** one managed identity per blast radius (app, payment, notification). Each is linked to a Kubernetes ServiceAccount through a federated credential.
- **How:** the subject `system:serviceaccount:<namespace>:<name>` ties the token to exactly one ServiceAccount. A pod using a different ServiceAccount can't get a token.
- **Least privilege:** the identity gets `Key Vault Secrets User`, which is read-only. The human admin gets `Secrets Officer`, assigned **once per vault**.
- **Honest trade-off:** payment and notification still share one vault with the app. The next step is a vault per sensitive service.

## 7. ci-identity
- **What:** one Entra ID app and service principal per environment for the pipeline.
- **How:** federated credentials that trust GitHub's OIDC token for this repo and environment only. There is no client secret, so nothing can leak or expire.
- **Scope:** `Contributor` on that environment's resource group only (not the subscription), `AcrPush` on the registry, and `Storage Blob Data Contributor` on the Terraform state account.

## 8. monitoring (new)
- **What:** a Log Analytics workspace per environment with 30-day retention and a 1 GB/day ingestion cap.
- **Why:** it's the audit trail for ACR, Key Vault and AKS. The daily cap keeps the cost predictable.

## 9. Platform-level controls
- **Remote state:** Azure Storage with AAD-only auth (`use_azuread_auth = true`), so no storage keys. State locking comes from the blob lease.
- **Separate state and identity per environment.**
- **Checkov scan** on every PR. The two accepted risks, public ACR and public Key Vault, are documented rather than hidden.
- **Budget alerts** at 50%, 80% forecast and 100%.

## 10. Closing: what I'd do next (shows maturity)
1. Private Endpoints for ACR and Key Vault (Premium ACR, self-hosted agent).
2. Separate Key Vault for payment.
3. Turn on Entra ID admin login and disable the static kubeconfig.
4. Give staging and prod separate AKS clusters (today staging shares dev's cluster).
5. Automated apply with approval gates.

## Likely examiner questions
- **Why OIDC and not a service-principal secret?** Secrets leak and expire. A federated token lasts minutes and only works from that repo and environment.
- **Why RBAC on Key Vault and not access policies?** It gives one access model with an audit trail.
- **What stops someone deleting prod?** Delete locks, RBAC scoped to the resource group, and approval gates.
- **What if two people apply at once?** Blob-lease state locking makes the second run fail safely.
