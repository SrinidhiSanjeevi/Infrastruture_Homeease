terraform {
  required_version = ">= 1.7.0"

 required_providers {
  azurerm = {
    source  = "hashicorp/azurerm"
    version = "~> 4.0"
  }
  random = {
    source  = "hashicorp/random"
    version = "~> 3.6"
  }
}

  backend "local" {
    path = "bootstrap.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# ============================================================
# Terraform Bootstrap Resource Group
# ============================================================

resource "azurerm_resource_group" "tfstate" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(var.tags, {
    component = "terraform-state"
  })
}

# ============================================================
# Terraform State Storage Account
# ============================================================

resource "random_string" "storage_suffix" {
  length  = 6

  special = false
  upper   = false
  numeric = true
}

resource "azurerm_storage_account" "tfstate" {
  name = "${var.storage_account_prefix}${random_string.storage_suffix.result}"

  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version = "TLS1_2"

  public_network_access_enabled = true

  blob_properties {
    versioning_enabled = true
  }

  tags = merge(var.tags, {
    component = "terraform-state"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================
# Terraform State Container
# ============================================================

resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}