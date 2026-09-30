# CI identity for GitHub Actions -> Terraform apply, prod only (no ADO/ACR-push identity here)

module "ci_identity" {
  source = "../../modules/ci-identity"

  environment              = var.environment
  application_display_name = "sp-homeease-ci-${var.environment}"

  acr_id = module.acr.id

  # Flip to true after setting the real ado_organization_id (pipeline needs it).
  enable_azure_devops         = false
  ado_organization_id         = var.ado_organization_id
  ado_organization_name       = var.ado_organization_name
  ado_project_name            = var.ado_project_name
  ado_service_connection_name = "azure-homeease-ci-${var.environment}"

  enable_github     = true
  github_owner      = "SrinidhiSanjeevi"
  github_repository = "Infrastruture_Homeease"
  # Matches `environment: ${{ matrix.env }}` in .github/workflows/terraform.yml.
  github_environment = var.environment

  enable_github_pull_request = false

  tfstate_storage_account_id = var.tfstate_storage_account_id

  # Scoped to THIS resource group only.
  enable_subscription_role_assignment = true
  subscription_role_scope             = module.resource_group.id
  subscription_role_definition        = "Contributor"
}

output "ci_client_id" {
  description = "Set as the GitHub Actions repository/environment variable AZURE_CLIENT_ID_PROD."
  value       = module.ci_identity.client_id
}

output "ci_tenant_id" {
  value = module.ci_identity.tenant_id
}

# ============================================================
# COST GUARDRAIL
# ============================================================

resource "azurerm_consumption_budget_resource_group" "homeease" {
  name              = "budget-homeease-${var.environment}"
  resource_group_id = module.resource_group.id

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 50
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }
}
