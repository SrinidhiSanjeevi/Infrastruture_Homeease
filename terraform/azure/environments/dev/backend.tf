# terraform/environments/dev/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeasegvz8nk"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
    use_azuread_auth     = true # <-- forces AAD token auth, never falls back to storage keys
  }
}