output "resource_group_name" {
  description = "HomeEase resource group name."
  value       = module.resource_group.name
}

output "vnet_id" {
  description = "HomeEase VNet resource ID."
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "HomeEase VNet name."
  value       = module.networking.vnet_name
}

output "aks_subnet_id" {
  description = "AKS subnet resource ID."
  value       = module.networking.aks_subnet_id
}

output "private_endpoint_subnet_id" {
  description = "Private Endpoint subnet resource ID."
  value       = module.networking.private_endpoint_subnet_id
}

output "acr_id" {
  description = "Azure Container Registry resource ID."
  value       = module.acr.id
}

output "acr_name" {
  description = "Azure Container Registry name."
  value       = module.acr.name
}

output "acr_login_server" {
  description = "Azure Container Registry login server."
  value       = module.acr.login_server
}

output "aks_id" {
  description = "AKS cluster resource ID."
  value       = module.aks.id
}

output "aks_name" {
  description = "AKS cluster name."
  value       = module.aks.name
}

output "aks_node_resource_group" {
  description = "Azure-managed AKS node resource group."
  value       = module.aks.node_resource_group
}

output "key_vault_id" {
  description = "Key Vault resource ID."
  value       = module.keyvault.id
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = module.keyvault.name
}

output "workload_identity_client_id" {
  description = "Client ID of the HomeEase workload identity."
  value       = module.workload_identity.client_id
}

output "workload_identity_principal_id" {
  description = "Principal ID of the HomeEase workload identity."
  value       = module.workload_identity.principal_id
}