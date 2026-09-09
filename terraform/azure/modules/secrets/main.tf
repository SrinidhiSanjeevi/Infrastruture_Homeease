# ============================================================
# Application secrets, declared as Key Vault entries.
#
# The VALUES still come from Azure DevOps secret variables at
# `terraform apply` time (never committed to git, never hardcoded
# here) — this only declares that these secrets MUST exist in
# Key Vault, and manages their lifecycle as code. Rotating a
# secret means changing the ADO variable and re-running apply,
# not manually clicking around the Key Vault blade.
# ============================================================

resource "azurerm_key_vault_secret" "mongo_uri" {
  name         = "mongo-uri"
  value        = var.mongo_uri
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "jwt-secret"
  value        = var.jwt_secret
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "email_user" {
  name         = "email-user"
  value        = var.email_user
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "email_pass" {
  name         = "email-pass"
  value        = var.email_pass
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "razorpay_key_id" {
  name         = "razorpay-key-id"
  value        = var.razorpay_key_id
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "razorpay_key_secret" {
  name         = "razorpay-key-secret"
  value        = var.razorpay_key_secret
  key_vault_id = var.key_vault_id
}