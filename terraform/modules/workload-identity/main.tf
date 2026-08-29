# ============================================================
# HomeEase User Assigned Managed Identity
# ============================================================
#
# This identity is used by HomeEase workloads running in AKS.
# No client secret or Azure credential is stored in Kubernetes.
#
# ============================================================

resource "azurerm_user_assigned_identity" "homeease" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# ============================================================
# AKS Workload Identity Federation
# ============================================================
#
# Allows the Kubernetes service account to exchange its OIDC
# token for an Azure AD token.
#
# No Azure client secret is required inside the application.
#
# The federated credential is tightly restricted to:
#
#   namespace:        var.namespace
#   service account:  var.service_account_name
#
# ============================================================

resource "azurerm_federated_identity_credential" "homeease" {
  name = var.federated_credential_name

  user_assigned_identity_id = azurerm_user_assigned_identity.homeease.id

  issuer = var.aks_oidc_issuer_url

  subject = "system:serviceaccount:${var.namespace}:${var.service_account_name}"

  audience = [
    "api://AzureADTokenExchange"
  ]
}

# ============================================================
# Key Vault Access
# ============================================================
#
# Grants ONLY the workload identity permission to read secrets.
#
# The identity does NOT receive:
#   - Key Vault Administrator
#   - Key Vault Secrets Officer
#   - permission to create/update/delete secrets
#
# This follows least-privilege access.
#
# ============================================================

resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"

  principal_id = azurerm_user_assigned_identity.homeease.principal_id
}