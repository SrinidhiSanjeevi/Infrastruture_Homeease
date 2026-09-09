# ============================================================
# CI IDENTITY WIRING — add to terraform/azure/environments/dev/
#
# Two-step apply, because the ADO service connection needs the client
# ID this produces:
#
#   1. Pick the service connection NAME (do not create it yet).
#      Put it in ado_service_connection_name below.
#   2. terraform apply
#   3. Read `terraform output ci_client_id` and `ci_tenant_id`.
#   4. In ADO: Project settings -> Service connections -> New ->
#      Azure Resource Manager -> Workload Identity federation (MANUAL).
#      Paste the client ID, tenant ID and subscription ID. Name it
#      EXACTLY what you put in step 1 — the name is part of the
#      subject claim, and a mismatch produces AADSTS700213 with a
#      message that does not tell you the name is the problem.
# ============================================================

module "ci_identity" {
  source = "../../modules/ci-identity"

  environment              = var.environment
  application_display_name = "sp-homeease-ci-${var.environment}"

  acr_id = module.acr.id

  # ── Azure DevOps (app repo -> ACR) ──────────────────────
  enable_azure_devops = true

  # GUID, not the org name. Get it from:
  #   https://dev.azure.com/<org>/_apis/connectionData  -> instanceId
  ado_organization_id         = var.ado_organization_id
  ado_organization_name       = var.ado_organization_name
  ado_project_name            = var.ado_project_name
  ado_service_connection_name = "azure-homeease-ci"

  # ── GitHub Actions (infra repo -> Terraform) ────────────
  enable_github     = true
  github_owner      = "SrinidhiSanjeevi"
  github_repository = "Infrastruture_Homeease"

  # Note: this identity CAN write state. For a stricter setup,
  # instantiate the module twice — one identity with Storage Blob Data
  # Contributor trusted for refs/heads/main, one with Storage Blob Data
  # Reader trusted for pull_request. Then a PR plan physically cannot
  # mutate state, rather than merely being expected not to.
  enable_github_pull_request = false

  tfstate_storage_account_id = var.tfstate_storage_account_id

  # Scoped to the resource group, not the subscription.
  subscription_role_scope      = module.resource_group.id
  subscription_role_definition = "Contributor"
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

# ============================================================
# COST GUARDRAIL
#
# On a 30-day, $200 credit this is not optional. Create it before the
# expensive resources, not after the email arrives.
# ============================================================

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
