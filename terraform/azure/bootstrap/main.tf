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

  # The state account created below also stores this root's own state.
  # One-time move from the old local file:
  #   terraform init -migrate-state -force-copy
  # Then keep the local bootstrap.tfstate* files only as a backup.
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatehomeeaseayhiue"
    container_name       = "tfstate"
    key                  = "bootstrap.terraform.tfstate"
    use_azuread_auth     = true
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
  length = 6

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

    # Recovery from accidental delete/overwrite of a state file.
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
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
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# State data-plane access for the bootstrapping user (use_azuread_auth = true needs this, Owner/Contributor alone is not enough)

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "tfstate_blob_contributor" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ============================================================
# Azure DevOps pipeline identity (service connection azure-homeease-dev)
#
# Lives HERE, not in an environment, so it survives a dev destroy/re-apply:
# the pipeline needs these roles to rebuild dev in the first place.
# ============================================================

# Read/write Terraform state (backend uses use_azuread_auth = true).
resource "azurerm_role_assignment" "pipeline_tfstate" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.pipeline_principal_object_id
  principal_type       = "ServicePrincipal"
}

# The stack creates role assignments (AcrPull, AcrPush, Key Vault roles).
# Role Based Access Control Administrator, restricted by an ABAC condition so
# the pipeline can assign ONLY those roles and can never hand out Owner or
# User Access Administrator. Subscription scope because the resource groups it
# works in are created and destroyed by the pipeline itself.
locals {
  pipeline_delegable_roles = join(", ", [
    "7f951dda-4ed3-4680-a7ca-43fe172d538d", # AcrPull
    "8311e382-0749-4cb8-b61a-304f252e45ec", # AcrPush
    "4633458b-17de-408a-b874-0445c86b69e6", # Key Vault Secrets User
    "b86a8fe4-44ce-4948-aee5-eccb2c155cd7", # Key Vault Secrets Officer
    "ba92f5b4-2d11-453d-a403-e96b0029c9fe", # Storage Blob Data Contributor
  ])
}

resource "azurerm_role_assignment" "pipeline_rbac_admin" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = var.pipeline_principal_object_id
  principal_type       = "ServicePrincipal"

  description       = "HomeEase pipeline: may only create/delete the role assignments listed in the condition."
  condition_version = "2.0"
  condition         = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.pipeline_delegable_roles}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.pipeline_delegable_roles}}
     )
    )
  EOT
}

# Policy assignments (e.g. the required-tags policy in environments/dev) are
# not covered by Contributor. This role is limited to policy objects only.
resource "azurerm_role_assignment" "pipeline_policy" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Resource Policy Contributor"
  principal_id         = var.pipeline_principal_object_id
  principal_type       = "ServicePrincipal"
}

# ============================================================
# Read-only PLAN identity (service connection azure-homeease-plan)
#
# plan jobs can read everything and the state, but cannot change Azure.
# Only the apply identity above has write access. Optional: created once
# plan_principal_object_id is set.
# ============================================================

resource "azurerm_role_assignment" "plan_reader" {
  count = var.plan_principal_object_id == null ? 0 : 1

  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = var.plan_principal_object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "plan_tfstate_reader" {
  count = var.plan_principal_object_id == null ? 0 : 1

  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.plan_principal_object_id
  principal_type       = "ServicePrincipal"
}
