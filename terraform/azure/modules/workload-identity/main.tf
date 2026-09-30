# User-assigned managed identity for HomeEase workloads running in AKS

resource "azurerm_user_assigned_identity" "homeease" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# Federated credential letting the Kubernetes service account exchange its OIDC token for an Azure AD token

resource "azurerm_federated_identity_credential" "homeease" {
  name = var.federated_credential_name

  user_assigned_identity_id = azurerm_user_assigned_identity.homeease.id

  issuer = var.aks_oidc_issuer_url

  subject = "system:serviceaccount:${var.namespace}:${var.service_account_name}"

  audience = [
    "api://AzureADTokenExchange"
  ]
}

# Additional federated ServiceAccounts sharing this same identity

resource "azurerm_federated_identity_credential" "additional" {
  for_each = {
    for sa in var.additional_service_accounts :
    "${sa.namespace}/${sa.service_account_name}" => sa
  }

  # Namespace-qualified only when it isn't the identity's home namespace,
  # so existing credentials keep their names (Azure name is ForceNew).
  # Without the qualifier, two namespaces sharing a service_account_name
  # (e.g. "admin-backend" in both the home namespace and a Phase-1-shared
  # one) would collide on the same Azure resource name.
  name = each.value.namespace == var.namespace ? "${var.federated_credential_name}-${each.value.service_account_name}" : "${var.federated_credential_name}-${each.value.service_account_name}-${each.value.namespace}"

  user_assigned_identity_id = azurerm_user_assigned_identity.homeease.id

  issuer = var.aks_oidc_issuer_url

  subject = "system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"

  audience = [
    "api://AzureADTokenExchange"
  ]
}

# Key Vault access: least-privilege, read-only (Key Vault Secrets User)

resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"

  principal_id = azurerm_user_assigned_identity.homeease.principal_id
}

# Human admin assignment: create it from ONE identity module per vault only.
# Azure rejects a second identical (principal, role, scope) assignment.
resource "azurerm_role_assignment" "admin_secrets_officer" {
  count = var.admin_object_id != null ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.admin_object_id
}