output "id" {
  description = "Resource ID of the Azure Container Registry."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Azure Container Registry name."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "ACR login server used for container image references."
  value       = azurerm_container_registry.this.login_server
}