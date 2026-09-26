# Remote state for prod. Same storage account and container as dev
# (bootstrap output); only the key differs per environment.

terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeaseayhiue"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"

    # Forces Entra token auth. Without it Terraform can silently fall
    # back to shared storage account keys — a long-lived credential
    # that defeats the OIDC setup used everywhere else.
    use_azuread_auth = true
  }
}
