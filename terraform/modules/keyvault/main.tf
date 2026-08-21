resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  tenant_id = var.tenant_id

  sku_name = var.sku_name

  # ==========================================================
  # Security
  # ==========================================================

  enable_rbac_authorization = true

  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # Public access is retained for the current capstone.
  # Private Endpoint can be added later.
  public_network_access_enabled = var.public_network_access_enabled

  tags = var.tags
}