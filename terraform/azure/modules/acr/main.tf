resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku = var.sku

  # Do not use the ACR admin username/password.
  # AKS uses managed identity + AcrPull instead.
  admin_enabled = false

  # Public endpoint is intentionally enabled for the current
  # Azure DevOps architecture.
  # Private Endpoint can be introduced later when the
  # Azure DevOps agent has VNet connectivity.
  public_network_access_enabled = var.public_network_access_enabled

  # Images must always require authentication.
  anonymous_pull_enabled = false

  # Premium only: untagged manifests are purged automatically.
  retention_policy_in_days = var.sku == "Premium" ? var.retention_policy_in_days : null

  tags = var.tags
}

# Audit trail: every login, push and pull is logged.
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

# Stops accidental `terraform destroy` / portal deletion of the registry.
resource "azurerm_management_lock" "this" {
  count = var.enable_delete_lock ? 1 : 0

  name       = "lock-${var.name}"
  scope      = azurerm_container_registry.this.id
  lock_level = "CanNotDelete"
  notes      = "Registry holds every environment's images. Remove the lock deliberately before deleting."
}