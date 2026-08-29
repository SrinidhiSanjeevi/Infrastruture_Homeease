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
# ============================================================

module "workload_identity" {
  source = "../../modules/workload-identity"

  identity_name = "id-homeease-${var.environment}"

  federated_credential_name = "fic-homeease-${var.environment}"

  resource_group_name = module.resource_group.name

  location = var.location

  aks_oidc_issuer_url = module.aks.oidc_issuer_url

  namespace            = var.kubernetes_namespace
  service_account_name = var.service_account_name

  key_vault_id = module.keyvault.id

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

