# ============================================================
# MISSING FILE — this is finding #5 in ANALYSIS.md.
#
# terraform/azure/environments/prod/ currently has NO backend
# block, so Terraform defaults to LOCAL state. On a CI runner that
# state file is created, used, and thrown away with the workspace.
# The next run has no record of what exists and tries to create
# everything again — which fails on globally-unique names (the ACR)
# and silently orphans whatever did succeed.
#
# Only the `key` differs between environments.
# ============================================================

terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeasegvz8nk"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"

    # Forces Entra token auth. Without it Terraform can silently fall
    # back to shared storage account keys — a long-lived credential
    # that defeats the OIDC setup used everywhere else.
    use_azuread_auth = true
  }
}
