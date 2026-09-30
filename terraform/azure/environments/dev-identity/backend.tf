terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeaseayhiue"
    container_name       = "tfstate"
    key                  = "dev-identity.terraform.tfstate"
    use_azuread_auth     = true
  }
}
