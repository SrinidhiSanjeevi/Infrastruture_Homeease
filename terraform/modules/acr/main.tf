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

  tags = var.tags
}