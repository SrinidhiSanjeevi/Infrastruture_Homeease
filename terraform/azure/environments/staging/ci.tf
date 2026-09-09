# ============================================================
# CI IDENTITY — GitHub Actions -> Terraform apply, staging only
#
# Unlike dev, this environment does NOT get an Azure DevOps /
# ACR-push identity: CI builds and scans exactly one image digest
# per commit, from dev's pipeline (see ANALYSIS.md §3). Staging
# never rebuilds — it receives the digest CD promotes into it.
# What staging DOES need is its own least-privilege identity for the
# infra repo's GitHub Actions workflow to plan/apply *this*
# environment, scoped to *this* resource group only — not dev's,
# not prod's.
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

  # Same trade-off as dev: one identity, both main (apply) and PR
  # (plan) trust it. See dev/ci.tf for the stricter two-identity
  # alternative if this is ever pushed toward real production use.
  enable_github_pull_request = false

  tfstate_storage_account_id = var.tfstate_storage_account_id

  # Scoped to THIS resource group, not the subscription and not
  # dev's or prod's resource group.
  subscription_role_scope      = module.resource_group.id
  subscription_role_definition = "Contributor"
}

output "ci_client_id" {
  description = "Set as the GitHub Actions repository/environment variable AZURE_CLIENT_ID_STAGING."
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
