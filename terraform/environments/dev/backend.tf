terraform {
  backend "azurerm" {
     resource_group_name  = "tfstate-rg"
     storage_account_name = "tfstatehomeease<suffix-from-bootstrap-output>"
     container_name       = "tfstate"
     key                  = "dev.terraform.tfstate"
  }
}