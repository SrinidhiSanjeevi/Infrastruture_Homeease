output "client_id" {
  description = "Paste this into the ADO service connection (Service Principal Id) or the GitHub AZURE_CLIENT_ID variable."
  value       = azuread_application.ci.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal — use this for any additional role assignments."
  value       = azuread_service_principal.ci.object_id
}

output "tenant_id" {
  description = "Entra tenant ID for the service connection / workflow."
  value       = data.azuread_client_config.current.tenant_id
}

output "ado_subject" {
  description = "The exact subject claim the ADO service connection must present. Mismatch here is the #1 cause of AADSTS700213."
  value       = var.enable_azure_devops ? "sc://${var.ado_organization_name}/${var.ado_project_name}/${var.ado_service_connection_name}" : null
}

output "ado_issuer" {
  description = "Issuer URL registered for Azure DevOps."
  value       = var.enable_azure_devops ? "https://vstoken.dev.azure.com/${var.ado_organization_id}" : null
}
