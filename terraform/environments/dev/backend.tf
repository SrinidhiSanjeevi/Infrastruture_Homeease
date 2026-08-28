terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeasegvz8nk"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
