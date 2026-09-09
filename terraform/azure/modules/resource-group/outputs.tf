output "id" {
  description = "Resource ID of the application resource group."
  value       = azurerm_resource_group.this.id
}

output "name" {
  description = "Name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Location of the application resource group."
  value       = azurerm_resource_group.this.location
}