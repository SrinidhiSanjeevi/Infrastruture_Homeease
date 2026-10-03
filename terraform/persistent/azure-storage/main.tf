resource "azurerm_resource_group" "images" {
  name     = "rg-${var.project_name}-data"
  location = var.location

  tags = {
    project    = var.project_name
    purpose    = "persistent-image-storage"
    managed_by = "terraform"
  }
}

resource "azurerm_storage_account" "images" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.images.name
  location            = azurerm_resource_group.images.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  allow_nested_items_to_be_public = false

  tags = {
    project    = var.project_name
    purpose    = "application-images"
    managed_by = "terraform"
  }
}

resource "azurerm_storage_container" "services" {
  name                  = "service-images"
  storage_account_id    = azurerm_storage_account.images.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "professionals" {
  name                  = "professional-images"
  storage_account_id    = azurerm_storage_account.images.id
  container_access_type = "private"
}

# The identity lives in environments/dev; apply that root first. Looking it up by name keeps this
# grant correct after the cluster/identities are rebuilt (a hard-coded ID went stale and broke images).
data "azurerm_user_assigned_identity" "app" {
  count               = var.workload_identity_principal_id == null ? 1 : 0
  name                = var.workload_identity_name
  resource_group_name = var.workload_identity_resource_group_name
}

resource "azurerm_role_assignment" "blob_data_contributor" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = coalesce(var.workload_identity_principal_id, one(data.azurerm_user_assigned_identity.app[*].principal_id))
  principal_type       = "ServicePrincipal"
}
