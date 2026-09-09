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