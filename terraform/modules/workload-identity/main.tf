# ============================================================
# HomeEase User Assigned Managed Identity
# ============================================================

resource "azurerm_user_assigned_identity" "homeease" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# ============================================================
# AKS Workload Identity Federation
#
# Allows Kubernetes workloads to authenticate to Azure
# without storing Azure credentials inside Kubernetes.
# ============================================================

resource "azurerm_federated_identity_credential" "homeease" {
  name                = var.federated_credential_name
  resource_group_name = var.resource_group_name

  parent_id = azurerm_user_assigned_identity.homeease.id

  issuer = var.aks_oidc_issuer_url

  subject = "system:serviceaccount:${var.namespace}:${var.service_account_name}"

  audience = [
    "api://AzureADTokenExchange"
  ]
}

# ============================================================
# Key Vault Access
#
# Grants the HomeEase workload identity permission to read
# secrets from Azure Key Vault using Azure RBAC.
# ============================================================

resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"

  principal_id = azurerm_user_assigned_identity.homeease.principal_id
}