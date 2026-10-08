# CI identity (Azure DevOps + GitHub Actions) using federated credentials instead of secrets.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

data "azuread_client_config" "current" {}

# APPLICATION + SERVICE PRINCIPAL

resource "azuread_application" "ci" {
  display_name     = var.application_display_name
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"

  # No API permissions are requested.
}

resource "azuread_service_principal" "ci" {
  client_id                    = azuread_application.ci.client_id
  owners                       = [data.azuread_client_config.current.object_id]
  app_role_assignment_required = false

  description = "CI push identity for HomeEase (${var.environment}). Credentials are federated; no client secret exists."

  tags = ["homeease", "ci", var.environment]
}

# Federated credential for the Azure DevOps service connection

resource "azuread_application_federated_identity_credential" "azure_devops" {
  count = var.enable_azure_devops ? 1 : 0

  # azuread v3: this is the application's RESOURCE ID (/applications/<uuid>), not the client ID.
  application_id = azuread_application.ci.id

  display_name = "ado-${var.ado_project_name}-${var.ado_service_connection_name}"
  description  = "Azure DevOps workload identity federation for the HomeEase CI pipeline"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://vstoken.dev.azure.com/${var.ado_organization_id}"
  subject   = "sc://${var.ado_organization_name}/${var.ado_project_name}/${var.ado_service_connection_name}"
}

# Federated credentials for GitHub Actions OIDC (main branch, environment, and PR subjects)

resource "azuread_application_federated_identity_credential" "github_main" {
  count = var.enable_github ? 1 : 0

  application_id = azuread_application.ci.id
  display_name   = "github-${var.github_repository}-main"
  description    = "GitHub Actions on refs/heads/main"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/main"
}

# Each terraform.yml job runs in a GitHub Environment (dev|staging|prod)
resource "azuread_application_federated_identity_credential" "github_environment" {
  count = var.enable_github && var.github_environment != null ? 1 : 0

  application_id = azuread_application.ci.id
  display_name   = "github-${var.github_repository}-env-${var.github_environment}"
  description    = "GitHub Actions jobs running in the ${var.github_environment} GitHub Environment"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_owner}/${var.github_repository}:environment:${var.github_environment}"
}

resource "azuread_application_federated_identity_credential" "github_pr" {
  count = var.enable_github && var.enable_github_pull_request ? 1 : 0

  application_id = azuread_application.ci.id
  display_name   = "github-${var.github_repository}-pr"
  description    = "GitHub Actions on pull requests — plan/read only, never granted push"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_owner}/${var.github_repository}:pull_request"
}

# Role assignment: AcrPush only

resource "azurerm_role_assignment" "acr_push" {
  scope                = var.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.ci.object_id

  description = "Allows the CI pipeline to push images. Pull for workloads is granted separately to the kubelet identity."
}

# Optional Terraform state access for the infra repo's CI identity

resource "azurerm_role_assignment" "tfstate_contributor" {
  count = var.tfstate_storage_account_id != null ? 1 : 0

  scope                = var.tfstate_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.ci.object_id

  description = "Read/write Terraform state. Paired with use_azuread_auth = true so storage account keys are never used."
}

resource "azurerm_role_assignment" "subscription_scope" {
  # A plain bool, not "scope != null"
  count = var.enable_subscription_role_assignment ? 1 : 0

  scope                = var.subscription_role_scope
  role_definition_name = var.subscription_role_definition
  principal_id         = azuread_service_principal.ci.object_id

  description = "Terraform apply permissions, scoped to a resource group rather than the whole subscription wherever possible."
}
