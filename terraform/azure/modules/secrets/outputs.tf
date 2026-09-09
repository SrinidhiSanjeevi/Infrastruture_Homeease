output "secret_names" {
  description = "Names of the secrets written to Key Vault, for reference by the SecretProviderClass."
  value = [
    azurerm_key_vault_secret.mongo_uri.name,
    azurerm_key_vault_secret.jwt_secret.name,
    azurerm_key_vault_secret.email_user.name,
    azurerm_key_vault_secret.email_pass.name,
    azurerm_key_vault_secret.razorpay_key_id.name,
    azurerm_key_vault_secret.razorpay_key_secret.name,
  ]
}