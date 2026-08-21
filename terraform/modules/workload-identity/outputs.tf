output "client_id" {
  description = "Client ID of the HomeEase user-assigned managed identity."
  value       = azurerm_user_assigned_identity.homeease.client_id
}

output "principal_id" {
  description = "Principal ID of the HomeEase user-assigned managed identity."
  value       = azurerm_user_assigned_identity.homeease.principal_id
}

output "identity_id" {
  description = "Resource ID of the HomeEase user-assigned managed identity."
  value       = azurerm_user_assigned_identity.homeease.id
}

output "federated_credential_id" {
  description = "Resource ID of the AKS federated identity credential."
  value       = azurerm_federated_identity_credential.homeease.id
}