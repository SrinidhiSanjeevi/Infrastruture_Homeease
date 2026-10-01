resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku = var.sku

  admin_enabled = false

  public_network_access_enabled = var.public_network_access_enabled

  anonymous_pull_enabled = false


  retention_policy_in_days = var.sku == "Premium" ? var.retention_policy_in_days : null

  tags = var.tags
}


resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
}


resource "azurerm_management_lock" "this" {
  count = var.enable_delete_lock ? 1 : 0

  name       = "lock-${var.name}"
  scope      = azurerm_container_registry.this.id
  lock_level = "CanNotDelete"
  notes      = "Registry holds every environment's images. Remove the lock deliberately before deleting."
}