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
# MONITORING (audit logs for ACR / Key Vault / AKS)
# ============================================================

module "monitoring" {
  source = "../../modules/monitoring"

  name                = "log-homeease-${var.environment}"
  resource_group_name = module.resource_group.name
  location            = var.location

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

  name                = "acrhomeease${var.environment}01" # "01": old name still held by the expired subscription
  resource_group_name = module.resource_group.name
  location            = var.location

  sku = var.acr_sku

  public_network_access_enabled = var.public_network_access_enabled

  enable_diagnostics         = true
  log_analytics_workspace_id = module.monitoring.id
  enable_delete_lock         = false

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

  # Hardening switches: off until values are supplied in dev.tfvars.
  admin_group_object_ids          = var.aks_admin_group_object_ids
  local_account_disabled          = var.aks_local_account_disabled
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges

  enable_diagnostics         = true
  log_analytics_workspace_id = module.monitoring.id
  enable_delete_lock         = false

  tags = local.common_tags
}

# ============================================================
# KEY VAULT
# ============================================================

module "keyvault" {
  source = "../../modules/keyvault"

  name                = "kv-${var.project_name}-${var.environment}-hs02" # "hs02": hs01 is held (purge protection) by the expired subscription
  location            = var.location
  resource_group_name = module.resource_group.name

  tenant_id = data.azurerm_client_config.current.tenant_id

  sku_name = var.keyvault_sku

  public_network_access_enabled = var.keyvault_public_network_access_enabled

  # Firewall: deny by default, allow the AKS subnet and named admin IPs.
  network_acls = var.keyvault_restrict_network ? {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.keyvault_allowed_ip_ranges
    virtual_network_subnet_ids = [module.networking.aks_subnet_id]
  } : null

  enable_diagnostics         = true
  log_analytics_workspace_id = module.monitoring.id
  enable_delete_lock         = false

  tags = local.common_tags
}


# AKS workload identities — one per blast radius (app, payment, notification)

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
    },
    # Phase 1: staging shares this identity (same AKS cluster) for now
    {
      namespace            = "homeease-staging"
      service_account_name = "backend"
    },
    {
      namespace            = "homeease-staging"
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
  additional_service_accounts = [
    # Phase 1: staging shares this identity (same AKS cluster) for now
    {
      namespace            = "homeease-staging"
      service_account_name = "payment-service"
    }
  ]

  # TODO: give payment-service its own Key Vault for real isolation
  key_vault_id = module.keyvault.id

  tags = local.common_tags
}

module "workload_identity_notification" {
  source = "../../modules/workload-identity"

  identity_name = "id-homeease-notification-${var.environment}"

  federated_credential_name = "fic-homeease-notification-${var.environment}"

  resource_group_name = module.resource_group.name

  location = var.location

  aks_oidc_issuer_url = module.aks.oidc_issuer_url

  namespace            = var.kubernetes_namespace
  service_account_name = "notification-service"
  additional_service_accounts = [
    # Phase 1: staging shares this identity (same AKS cluster) for now
    {
      namespace            = "homeease-staging"
      service_account_name = "notification-service"
    }
  ]

  # Same shared-vault trade-off as workload_identity_payment above
  key_vault_id = module.keyvault.id

  tags = local.common_tags
}

# ============================================================
# ALERTS (AKS CPU / memory -> e-mail)
# ============================================================

module "alerts" {
  source = "../../modules/alerts"

  name_prefix         = "homeease-${var.environment}"
  resource_group_name = module.resource_group.name
  aks_id              = module.aks.id
  email_addresses     = var.budget_contact_emails

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

