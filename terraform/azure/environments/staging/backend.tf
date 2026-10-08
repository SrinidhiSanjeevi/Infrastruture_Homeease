# Remote state for staging.

terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeaseayhiue"
    container_name       = "tfstate"
    key                  = "staging.terraform.tfstate"

    # Forces Entra token auth.
    use_azuread_auth = true
  }
}
