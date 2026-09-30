output "ci_client_id" {
  description = "Client ID of the dev CI identity."
  value       = module.ci_identity.client_id
}

output "ci_tenant_id" {
  value = module.ci_identity.tenant_id
}

output "ci_ado_subject" {
  description = "Subject the Azure DevOps service connection must present."
  value       = module.ci_identity.ado_subject
}
