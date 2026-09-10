# ============================================================
# RESOURCE GROUP
# ============================================================

module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-homeease-${var.environment}"
  location = var.location

  tags = local.common_tags
}

# ============================================================
# NETWORKING
# ============================================================

module "networking" {
  source = "../../modules/networking"

  resource_group_name = module.resource_group.name
  location            = var.location
  environment         = var.environment

  vnet_address_space             = var.vnet_address_space
  aks_subnet_prefix              = var.aks_subnet_prefix
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix

  tags = local.common_tags
}

# ============================================================
# AZURE CONTAINER REGISTRY
# ============================================================

module "acr" {
  source = "../../modules/acr"

  name                = "acrhomeease${var.environment}"
  resource_group_name = module.resource_group.name
  location            = var.location

  sku = var.acr_sku

  public_network_access_enabled = var.public_network_access_enabled

  tags = local.common_tags
}

# ============================================================
# AKS
# ============================================================

module "aks" {
  source = "../../modules/aks"

  name                = "aks-homeease-${var.environment}"
  resource_group_name = module.resource_group.name
  location            = var.location

  dns_prefix = "aks-homeease-${var.environment}"

  kubernetes_version = var.kubernetes_version

  subnet_id = module.networking.aks_subnet_id

  acr_id = module.acr.id

  sku_tier = var.aks_sku_tier

  node_count = var.aks_node_count
  vm_size    = var.aks_vm_size

  service_cidr   = var.service_cidr
  dns_service_ip = var.dns_service_ip

  tags = local.common_tags
}

# ============================================================
# KEY VAULT
# ============================================================

module "keyvault" {
  source = "../../modules/keyvault"

  name                = "kv-${var.project_name}-${var.environment}-hs01"
  location            = var.location
  resource_group_name = module.resource_group.name

  tenant_id = data.azurerm_client_config.current.tenant_id

  sku_name = var.keyvault_sku

  public_network_access_enabled = var.keyvault_public_network_access_enabled

  tags = local.common_tags
}


# ============================================================
# AKS WORKLOAD IDENTITY
#
# Two identities, not one, because Key Vault RBAC is granted at the
# VAULT level — Azure has no built-in per-secret role scoping. That
# means a shared identity is fine for services that are meant to see
# the same secrets, but doesn't buy any real isolation on its own.
#
#   workload_identity_app     -> ServiceAccounts "backend" AND
#                                 "admin-backend". Both already read
#                                 mongo-uri/jwt-secret/email-* (see
#                                 modules/keyvault/SECRETS.md) — one
#                                 identity, one blast radius, matches
#                                 reality instead of pretending they're
#                                 isolated when they're not.
#
#   workload_identity_payment -> ServiceAccount "payment-service"
#                                 ONLY. Same Key Vault for now (see
#                                 the trade-off note below), but its
#                                 OWN identity means: (a) Key Vault
#                                 diagnostic logs show a distinct
#                                 principal for payment's reads, not
#                                 blended into backend's traffic, and
#                                 (b) the day a payment-only Key Vault
#                                 is added, only THIS block's
#                                 key_vault_id changes — backend/
#                                 admin-backend are untouched.
#
# Namespace: matches the GitOps repo's namespace-per-environment
# design (homeease-dev / homeease-staging / homeease-prod), NOT a
# single shared "homeease" namespace — that was the bug (Terraform
# and the GitOps repo targeting different namespaces, so no pod could
# actually authenticate). var.kubernetes_namespace must be set to
# "homeease-${var.environment}" in tfvars for this to line up.
# ============================================================

module "workload_identity_app" {
  source = "../../modules/workload-identity"

  identity_name = "id-homeease-app-${var.environment}"

  federated_credential_name = "fic-homeease-app-${var.environment}"

  resource_group_name = module.resource_group.name

  location = var.location

  aks_oidc_issuer_url = module.aks.oidc_issuer_url

  namespace            = var.kubernetes_namespace
  service_account_name = var.service_account_name # "backend"
  additional_service_accounts = [
    {
      namespace            = var.kubernetes_namespace
      service_account_name = "admin-backend"
    }
  ]

  key_vault_id    = module.keyvault.id
  admin_object_id = var.admin_object_id

  tags = local.common_tags
}

module "workload_identity_payment" {
  source = "../../modules/workload-identity"

  identity_name = "id-homeease-payment-${var.environment}"

  federated_credential_name = "fic-homeease-payment-${var.environment}"

  resource_group_name = module.resource_group.name

  location = var.location

  aks_oidc_issuer_url = module.aks.oidc_issuer_url

  namespace            = var.kubernetes_namespace
  service_account_name = "payment-service"

  # TODO (future hardening, not done here): a SEPARATE Key Vault
  # scoped to only payment-service's secrets is what actually
  # achieves isolation, since RBAC is vault-wide. Sharing the vault
  # for now is a documented, deliberate trade-off — not an oversight.
  key_vault_id    = module.keyvault.id
  admin_object_id = var.admin_object_id

  tags = local.common_tags
}

# ============================================================
# COMMON TAGS
# ============================================================

locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
    owner       = "homeease"
  }
}

