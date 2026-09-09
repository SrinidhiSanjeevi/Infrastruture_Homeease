variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
}

variable "application_display_name" {
  description = "Display name of the Entra ID application used by CI."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the Azure Container Registry the pipeline pushes to."
  type        = string
}

# ── Azure DevOps ────────────────────────────────────────────

variable "enable_azure_devops" {
  description = "Register a federated credential for an Azure DevOps service connection."
  type        = bool
  default     = true
}

variable "ado_organization_id" {
  description = <<-EOT
    Azure DevOps ORGANIZATION ID (a GUID), not the org name.
    Find it at: https://dev.azure.com/<org>/_apis/connectionData
    -> instanceId. The issuer URL is built from this.
  EOT
  type        = string
  default     = null
}

variable "ado_organization_name" {
  description = "Azure DevOps organization NAME, used in the subject claim."
  type        = string
  default     = null
}

variable "ado_project_name" {
  description = "Azure DevOps project name."
  type        = string
  default     = null
}

variable "ado_service_connection_name" {
  description = "Name of the service connection you will create in ADO. Choose it before applying; it is part of the subject claim."
  type        = string
  default     = "azure-homeease-ci"
}

# ── GitHub ──────────────────────────────────────────────────

variable "enable_github" {
  description = "Register federated credentials for GitHub Actions."
  type        = bool
  default     = false
}

variable "github_owner" {
  description = "GitHub org or user."
  type        = string
  default     = null
}

variable "github_repository" {
  description = "GitHub repository name."
  type        = string
  default     = null
}

variable "enable_github_pull_request" {
  description = "Also trust the pull_request subject. Only enable for an identity that has READ permissions only."
  type        = bool
  default     = false
}

# ── Optional extra scopes ───────────────────────────────────

variable "tfstate_storage_account_id" {
  description = "Storage account holding Terraform state. Set only for the infra-repo identity."
  type        = string
  default     = null
}

variable "subscription_role_scope" {
  description = "Scope for the Terraform apply role. Prefer a resource group ID over a subscription ID."
  type        = string
  default     = null
}

variable "subscription_role_definition" {
  description = "Role granted at subscription_role_scope."
  type        = string
  default     = "Contributor"
}
