output "vnet_id" {
  description = "Resource ID of the HomeEase virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the HomeEase virtual network."
  value       = azurerm_virtual_network.this.name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet."
  value       = azurerm_subnet.aks.id
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet."
  value       = azurerm_subnet.private_endpoints.id
}