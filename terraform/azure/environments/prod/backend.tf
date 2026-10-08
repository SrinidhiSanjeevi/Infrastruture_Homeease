# Remote state for prod.

terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeaseayhiue"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"

    # Forces Entra token auth.
    use_azuread_auth = true
  }
}
