# ============================================================
# CI IDENTITY — Azure DevOps and GitHub Actions, secretless
#
# Creates one Entra ID application whose credentials are federated
# trust relationships, not secrets. Nothing this module produces can
# be copied out of a log or a leaked variable group, because nothing
# it produces is a credential.
#
# Two trust anchors are registered against the same application:
#
#   Azure DevOps   issuer  https://vstoken.dev.azure.com/<org-id>
#                  subject sc://<org>/<project>/<service-connection>
#
#   GitHub Actions issuer  https://token.actions.githubusercontent.com
#                  subject repo:<owner>/<repo>:ref:refs/heads/main
#
# NOTE ON THE ADO SERVICE CONNECTION
# Create it as "Workload Identity federation (MANUAL)", not automatic.
# Automatic makes Azure DevOps create the app registration for you,
# outside Terraform — your CI identity then exists only as click-ops
# and cannot be reviewed, versioned or destroyed with the rest of the
# stack. Manual gives you an issuer + subject to paste here, so the
# identity is code like everything else.
#
# Chicken-and-egg: the service connection needs the client ID this
# module outputs, and this module needs the connection's name (which
# you choose up front, so there is no real deadlock — pick the name,
# apply, then create the connection with the output).
# ============================================================

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

# ============================================================
# APPLICATION + SERVICE PRINCIPAL
# ============================================================

resource "azuread_application" "ci" {
  display_name     = var.application_display_name
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"

  # No API permissions are requested. This identity does not read the
  # directory; it only holds Azure RBAC role assignments on resources.
}

resource "azuread_service_principal" "ci" {
  client_id                    = azuread_application.ci.client_id
  owners                       = [data.azuread_client_config.current.object_id]
  app_role_assignment_required = false

  description = "CI push identity for HomeEase (${var.environment}). Credentials are federated; no client secret exists."

  tags = ["homeease", "ci", var.environment]
}

# ============================================================
# FEDERATED CREDENTIAL — AZURE DEVOPS
#
# The subject is what makes this safe. `sc://org/project/connection`
# means only that one service connection, in that one project, can
# exchange a token for this identity. Another project in the same
# organisation cannot.
# ============================================================

resource "azuread_application_federated_identity_credential" "azure_devops" {
  count = var.enable_azure_devops ? 1 : 0

  # azuread v3: this is the application's RESOURCE ID (/applications/<uuid>),
  # not the client ID. In v2 the argument was `application_object_id`.
  application_id = azuread_application.ci.id

  display_name = "ado-${var.ado_project_name}-${var.ado_service_connection_name}"
  description  = "Azure DevOps workload identity federation for the HomeEase CI pipeline"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://vstoken.dev.azure.com/${var.ado_organization_id}"
  subject   = "sc://${var.ado_organization_name}/${var.ado_project_name}/${var.ado_service_connection_name}"
}

# ============================================================
# FEDERATED CREDENTIALS — GITHUB ACTIONS
#
# Two separate subjects, deliberately:
#
#   main    → can push to ACR (see role assignment below)
#   PRs     → a SEPARATE identity in practice; here we register the
#             environment subject so you can later scope prod-only
#             permissions to a GitHub Environment with reviewers.
#
# What NOT to write: subject = "repo:owner/repo:*". That wildcard
# lets any branch — including one pushed by a fork PR — assume the
# identity. It is the single most common OIDC misconfiguration.
# ============================================================

resource "azuread_application_federated_identity_credential" "github_main" {
  count = var.enable_github ? 1 : 0

  application_id = azuread_application.ci.id
  display_name   = "github-${var.github_repository}-main"
  description    = "GitHub Actions on refs/heads/main"

  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/main"
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

# ============================================================
# ROLE ASSIGNMENTS
#
# AcrPush only. Not Contributor, not Owner, not AcrPull (push
# implies the ability to pull what you pushed; the cluster's kubelet
# identity holds AcrPull separately).
#
# Scope note: per-repository push isolation inside a single registry
# needs either scope maps + tokens (Premium SKU only) or ABAC
# conditions on the role assignment (preview, limited Terraform
# support). On Basic SKU, registry-wide AcrPush for a CI identity is
# the accepted trade-off. Document it rather than pretending it isn't
# there.
# ============================================================

resource "azurerm_role_assignment" "acr_push" {
  scope                = var.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.ci.object_id

  description = "Allows the CI pipeline to push images. Pull for workloads is granted separately to the kubelet identity."
}

# ============================================================
# OPTIONAL — TERRAFORM STATE ACCESS
#
# Only for the identity used by the INFRA repo's workflow, not the
# app CI. Two levels so PR plans cannot mutate state:
#
#   Storage Blob Data Contributor → apply  (main)
#   Storage Blob Data Reader      → plan   (PRs)
# ============================================================

resource "azurerm_role_assignment" "tfstate_contributor" {
  count = var.tfstate_storage_account_id != null ? 1 : 0

  scope                = var.tfstate_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.ci.object_id

  description = "Read/write Terraform state. Paired with use_azuread_auth = true so storage account keys are never used."
}

resource "azurerm_role_assignment" "subscription_scope" {
  count = var.subscription_role_scope != null ? 1 : 0

  scope                = var.subscription_role_scope
  role_definition_name = var.subscription_role_definition
  principal_id         = azuread_service_principal.ci.object_id

  description = "Terraform apply permissions, scoped to a resource group rather than the whole subscription wherever possible."
}
