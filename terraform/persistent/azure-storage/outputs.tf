output "resource_group_name" {
  description = "Resource group containing persistent HomeEase image storage."
  value       = azurerm_resource_group.images.name
}

output "storage_account_name" {
  description = "HomeEase image storage account name."
  value       = azurerm_storage_account.images.name
}

output "storage_account_id" {
  description = "Resource ID of the HomeEase image storage account."
  value       = azurerm_storage_account.images.id
}

output "blob_endpoint" {
  description = "Primary Blob service endpoint."
  value       = azurerm_storage_account.images.primary_blob_endpoint
}

output "service_container_name" {
  value = azurerm_storage_container.services.name
}

output "professional_container_name" {
  value = azurerm_storage_container.professionals.name
}