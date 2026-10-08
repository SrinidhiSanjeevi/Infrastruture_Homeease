# dev CI identity: its OWN root, applied manually (like bootstrap).

data "azurerm_resource_group" "this" {
  name = "rg-${var.project_name}-${var.environment}"
}

data "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = data.azurerm_resource_group.this.name
}

variable "project_name" {
  description = "Project name used in resource names."
  type        = string
  default     = "homeease"
}

module "ci_identity" {
  source = "../../modules/ci-identity"

  environment              = var.environment
  application_display_name = "sp-homeease-ci-${var.environment}"

  acr_id = data.azurerm_container_registry.this.id

  enable_azure_devops         = var.enable_azure_devops
  ado_organization_id         = var.ado_organization_id
  ado_organization_name       = var.ado_organization_name
  ado_project_name            = var.ado_project_name
  ado_service_connection_name = "azure-homeease-ci-${var.environment}"

  enable_github      = true
  github_owner       = var.github_owner
  github_repository  = var.github_repository
  github_environment = var.environment

  enable_github_pull_request = false

  tfstate_storage_account_id = var.tfstate_storage_account_id

  # Scoped to the resource group, not the subscription.
  enable_subscription_role_assignment = true
  subscription_role_scope             = data.azurerm_resource_group.this.id
  subscription_role_definition        = "Contributor"
}
