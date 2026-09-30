# CI identity wiring for dev (Azure DevOps + GitHub Actions)

module "ci_identity" {
  source = "../../modules/ci-identity"

  environment              = var.environment
  application_display_name = "sp-homeease-ci-${var.environment}"

  acr_id = module.acr.id

  # Azure DevOps (app repo -> ACR): temporarily off, ado_organization_id is still a placeholder
  # Flip to true after setting the real ado_organization_id (pipeline needs it).
  enable_azure_devops = false

  # GUID, not the org name. Get it from:
  #   https://dev.azure.com/<org>/_apis/connectionData  -> instanceId
  ado_organization_id   = var.ado_organization_id
  ado_organization_name = var.ado_organization_name
  ado_project_name      = var.ado_project_name
  # One service connection per environment: ADO names are unique per project.
  ado_service_connection_name = "azure-homeease-ci-${var.environment}"

  # ── GitHub Actions (infra repo -> Terraform) ────────────
  enable_github     = true
  github_owner      = "SrinidhiSanjeevi"
  github_repository = "Infrastruture_Homeease"
  # Matches `environment: ${{ matrix.env }}` in .github/workflows/terraform.yml.
  github_environment = var.environment

  # Note: this identity can write state (stricter two-identity split not used here)
  enable_github_pull_request = false

  tfstate_storage_account_id = var.tfstate_storage_account_id

  # Scoped to the resource group, not the subscription.
  enable_subscription_role_assignment = true
  subscription_role_scope             = module.resource_group.id
  subscription_role_definition        = "Contributor"
}

output "ci_client_id" {
  description = "Paste into the ADO service connection and the GitHub AZURE_CLIENT_ID variable."
  value       = module.ci_identity.client_id
}

output "ci_tenant_id" {
  value = module.ci_identity.tenant_id
}

output "ci_ado_subject" {
  description = "The subject the service connection must present. If ADO auth fails, compare this against what the connection sends."
  value       = module.ci_identity.ado_subject
}

# Cost guardrail budget

resource "azurerm_consumption_budget_resource_group" "homeease" {
  name              = "budget-homeease-${var.environment}"
  resource_group_id = module.resource_group.id

  amount     = var.monthly_budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date # first of a month, e.g. "2026-10-01T00:00:00Z"
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
