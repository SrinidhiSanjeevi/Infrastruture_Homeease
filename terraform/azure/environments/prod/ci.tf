# ============================================================
# CI IDENTITY — GitHub Actions -> Terraform apply, prod only
#
# Same reasoning as staging/ci.tf: no ADO/ACR-push identity here,
# because CI never rebuilds an image for prod — it promotes the
# digest already built, scanned and signed for dev. This identity
# exists only so the infra repo's GitHub Actions workflow can
# plan/apply THIS resource group.
#
# Because this is prod, prefer requiring a GitHub Environment with
# manual reviewers ("environment: prod" in the workflow) before this
# identity's token is ever minted, rather than trusting main alone.
# ============================================================

module "ci_identity" {
  source = "../../modules/ci-identity"

  environment              = var.environment
  application_display_name = "sp-homeease-ci-${var.environment}"

  acr_id = module.acr.id

  enable_azure_devops = false

  enable_github     = true
  github_owner      = "SrinidhiSanjeevi"
  github_repository = "Infrastruture_Homeease"

  enable_github_pull_request = false

  tfstate_storage_account_id = var.tfstate_storage_account_id

  # Scoped to THIS resource group only.
  subscription_role_scope      = module.resource_group.id
  subscription_role_definition = "Contributor"
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
