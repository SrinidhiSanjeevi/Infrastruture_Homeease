# HomeEase Infrastructure as Code (Terraform) — Personal Reference Notes

This repository contains the complete Infrastructure as Code (IaC) for **HomeEase** on Microsoft Azure. It provisions and manages all underlying cloud infrastructure required to host the containerized microservices platform.

---

## 1. Is Terraform 100% Complete as IaC?

**YES.** The cloud infrastructure is completely codified in Terraform. No Azure resources need to be created manually via the Azure Portal or ad-hoc Azure CLI scripts.

### What Terraform Owns vs What GitOps/Kubernetes Owns

```
┌────────────────────────────────────────────────────────────────────────┐
│                        AZURE CLOUD LAYER (Terraform)                   │
│                                                                        │
│  ┌────────────────┐   ┌────────────────┐   ┌────────────────────────┐  │
│  │ Resource Group │   │  VNet/Subnets  │   │ ACR Container Registry │  │
│  │ rg-homeease-dev│   │  & NSG Rules   │   │ acrhomeeasedev         │  │
│  └────────────────┘   └────────────────┘   └────────────────────────┘  │
│          │                    │                         │              │
│          ▼                    ▼                         ▼              │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    AKS Cluster (aks-homeease-dev)                │  │
│  │  • System Node Pool (Auto-scaling 1-3 nodes)                     │  │
│  │  • Azure CNI Overlay + Azure Network Policy                      │  │
│  │  • OIDC Issuer & Workload Identity Enabled                       │  │
│  │  • Key Vault CSI Secrets Store Add-on (Auto-rotation enabled)    │  │
│  │  • Kubelet AcrPull Role Assignment                               │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│          │                                              │              │
│          ▼                                              ▼              │
│  ┌─────────────────────────────────┐      ┌─────────────────────────┐  │
│  │  User Assigned Managed Identity │◄─────┤  Azure Key Vault (RBAC) │  │
│  │  + Federated Credential (FIC)   │      │  kv-homeease-dev-hs01   │  │
│  └─────────────────────────────────┘      └─────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                        Outputs flow to GitOps
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     KUBERNETES & GITOPS LAYER (Helm)                   │
│                                                                        │
│  • Namespaces (`homeease`, `monitoring`, `ingress-nginx`)              │
│  • ResourceQuotas & Zero-Trust Default-Deny NetworkPolicies           │
│  • ServiceAccount (`homeease`) annotated with Managed Identity Client ID│
│  • SecretProviderClass (`homeease-keyvault`) syncing KV secrets to K8s │
│  • Microservices: Backend, Admin-Backend, Frontend                     │
│  • Ingress-NGINX Controller, HPA Autoscalers, PDBs                     │
│  • Observability: Prometheus Operator, ServiceMonitors, Grafana        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Directory Structure & Architecture

```
Infrastruture_Homeease/
├── terraform/
│   ├── bootstrap/               # Stage 0: Sets up Azure Storage for remote .tfstate
│   │   ├── main.tf              # Resource Group + Storage Account + Blob Container
│   │   ├── variable.tf
│   │   └── outputs.tf
│   │
│   ├── modules/                 # Reusable, standalone building blocks
│   │   ├── resource-group/      # Creates Azure Resource Group with tags
│   │   ├── networking/          # VNet, AKS Subnet, PE Subnet, NSGs & associations
│   │   ├── acr/                 # Azure Container Registry (Basic SKU)
│   │   ├── aks/                 # AKS Cluster + CNI Overlay + CSI Provider + AcrPull
│   │   ├── keyvault/            # Azure Key Vault with Azure RBAC enabled
│   │   ├── workload-identity/   # UAMI + Federated Credential + KV Role Assignments
│   │   └── secrets/             # Key Vault secret declarations (Mongo URI, JWT, Razorpay)
│   │
│   └── environments/            # Environment-specific root modules
│       ├── dev/                 # Active environment (Central India, Cost-optimized)
│       │   ├── backend.tf       # Remote state configuration in Azure Blob Storage
│       │   ├── main.tf          # Instantiates all modules
│       │   ├── variables.tf     # Variable declarations
│       │   ├── terraform.tfvars # Concrete input values for Dev
│       │   ├── providers.tf     # AzureRM & Random provider configurations
│       │   └── outputs.tf       # Exported IDs, endpoints, and credentials
│       ├── staging/             # Pre-production environment configuration
│       └── prod/                # Production environment configuration
```

---

## 3. Detailed Component Breakdown: What, Why & How

### A. `bootstrap/` (Remote State Backend)
* **What**: Provisions a dedicated Storage Account (`tfstatehomeease...`) and Blob container (`tfstate`) in resource group `tfstate-rg`.
* **Why**: Team and CI/CD environments cannot store `terraform.tfstate` on local disks. Azure Blob storage provides centralized state with automatic state locking (preventing simultaneous modifications).
* **How it works**:
  - Run once with `backend "local"` to create the storage account.
  - Subsequent environments configure `backend "azurerm"` pointing to this container.
  - Uses `use_azuread_auth = true` so access uses Azure Entra ID tokens rather than static storage access keys.

---

### B. `modules/resource-group`
* **What**: Provisions the parent resource container `rg-homeease-dev`.
* **Why**: Logically groups all project resources for lifecycle management, access control, and billing attribution.
* **How it works**: Injects standard tags (`project=homeease`, `environment=dev`, `managed_by=terraform`).

---

### C. `modules/networking`
* **What**: 
  - Virtual Network (`vnet-homeease-dev` - `10.10.0.0/16`)
  - AKS Subnet (`snet-aks-dev` - `10.10.0.0/22`)
  - Private Endpoint Subnet (`snet-private-endpoints-dev` - `10.10.4.0/24`)
  - Network Security Group (`nsg-aks-dev`) with security rules for Azure Load Balancer, NodePorts (`30000-32767`), HTTP (`80`), and HTTPS (`443`).
* **Why**: Separates AKS cluster nodes and ingress traffic while reserving an isolated subnet for future private database endpoints.
* **How it works**: Connects the AKS subnet directly to the Network Security Group to filter inbound traffic at the Azure software-defined network boundary before reaching the cluster.

---

### D. `modules/acr` (Azure Container Registry)
* **What**: Private container registry (`acrhomeeasedev.azurecr.io`) with `Basic` SKU.
* **Why**: Secure, low-latency container image storage located in the same Azure region (`Central India`) as the AKS cluster.
* **How it works**: Enables admin user disabled by default for zero-trust security; images are pulled by AKS using native Azure Managed Identity.

---

### E. `modules/aks` (Azure Kubernetes Service)
* **What**: Managed Kubernetes cluster `aks-homeease-dev` (`Standard_D2s_v5`, 1-3 nodes).
* **Key Features Configured**:
  1. **Azure CNI Overlay (`network_plugin = "azure", network_plugin_mode = "overlay"`)**:
     - Pods receive private IP addresses from an overlay CIDR rather than depleting the Azure VNet subnet IPs.
  2. **Azure Network Policy (`network_policy = "azure"`)**:
     - Enforces Kubernetes NetworkPolicies at the Linux kernel level.
  3. **Auto-scaling Node Pool (`min_count = 1, max_count = 3`)**:
     - Dynamically adds nodes when CPU/Memory demand increases, and scales down to 1 node during low traffic to minimize costs.
  4. **Key Vault Secrets Provider Add-on (`key_vault_secrets_provider`)**:
     - Deploys the Secrets Store CSI driver natively inside AKS with automatic secret polling and rotation enabled.
  5. **Native ACR Pull Role Assignment (`azurerm_role_assignment.aks_acr_pull`)**:
     - Automatically grants the AKS Kubelet Identity the `AcrPull` role on the ACR registry. No `imagePullSecrets` or Docker credentials need to be stored in Kubernetes.

---

### F. `modules/keyvault` & `modules/workload-identity` (Passwordless Secret Security)
* **What**: 
  - Azure Key Vault (`kv-homeease-dev-hs01`) with RBAC authorization, purge protection, and soft delete.
  - User-Assigned Managed Identity (`id-homeease-dev`).
  - Federated Identity Credential (`fic-homeease-dev`) linking the Kubernetes ServiceAccount `homeease:homeease` with Azure Entra ID.
* **Why**: **Completely eliminates hardcoded database passwords, API tokens, and JWT secrets from source code, Git, and container images.**
* **How Azure Workload Identity Works (Step-by-Step)**:
  1. AKS has OIDC issuer enabled (`oidc_issuer_url`).
  2. Terraform creates a User-Assigned Managed Identity (`id-homeease-dev`) and grants it the `Key Vault Secrets User` role on the Key Vault.
  3. Terraform creates a **Federated Identity Credential** that tells Azure: *"Trust any OIDC token minted by this AKS cluster for the ServiceAccount `homeease:homeease`"*.
  4. When backend pods start in Kubernetes with `azure.workload.identity/use: "true"`, the AKS Workload Identity webhook projects an Azure AD token into the container.
  5. The Secrets Store CSI driver uses this token to retrieve `mongo-uri`, `jwt-secret`, and `razorpay` keys directly from Azure Key Vault and project them into the pod environment.

---

## 4. How Terraform Connects to GitOps (The Hand-off)

Terraform outputs the exact configuration parameters that the GitOps repository consumes:

| Terraform Output | Value (Dev) | Where Used in GitOps |
|---|---|---|
| `workload_identity_client_id` | `3e6bc199-1c53-401b-a1ea-1d0de3b82275` | Injected into `platform/serviceaccount.yaml` and `environments/dev/backend-values.yaml` |
| `key_vault_name` | `kv-homeease-dev-hs01` | Injected into `platform/secretproviderclass.yaml` |
| `acr_login_server` | `acrhomeeasedev.azurecr.io` | Injected into `charts/*/values.yaml` (`image.repository`) |
| `resource_group_name` | `rg-homeease-dev` | Injected into Key Vault CSI tenant configuration |

---

## 5. Terraform Commands Cheat Sheet

### Running Terraform Locally

```bash
# 1. Login to Azure CLI
az login --tenant <TENANT_ID>
az account set --subscription <SUBSCRIPTION_ID>

# 2. Navigate to dev environment
cd /home/vboxuser/Desktop/HomeEase/Infrastruture_Homeease/terraform/environments/dev

# 3. Initialize working directory & download provider plugins
terraform init

# 4. Validate syntax and configuration
terraform validate

# 5. Review execution plan
terraform plan -out=tfplan

# 6. Apply infrastructure changes
terraform apply tfplan

# 7. View outputs
terraform output
```

### Inspecting State & Resources

```bash
# List all resources tracked in state
terraform state list

# Show details of a specific resource
terraform state show module.aks.azurerm_kubernetes_cluster.this

# View output values in JSON
terraform output -json
```
