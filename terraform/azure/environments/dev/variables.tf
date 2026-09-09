variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition = contains(
      ["dev", "staging", "prod"],
      var.environment
    )

    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "project_name" {
  description = "Application/project name."
  type        = string
}

# ============================================================
# AKS
# ============================================================

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Null uses the Azure-supported default."
  type        = string
  default     = null
}

variable "aks_node_count" {
  description = "Number of AKS nodes."
  type        = number

  validation {
    condition     = var.aks_node_count >= 1
    error_message = "AKS node count must be at least 1."
  }
}

variable "aks_vm_size" {
  description = "VM size used by AKS nodes."
  type        = string
}

variable "aks_sku_tier" {
  description = "AKS pricing tier."
  type        = string

  validation {
    condition = contains(
      ["Free", "Standard"],
      var.aks_sku_tier
    )

    error_message = "AKS SKU tier must be Free or Standard."
  }
}

variable "service_cidr" {
  description = "Kubernetes service CIDR."
  type        = string
  default     = "10.20.0.0/16"
}

variable "dns_service_ip" {
  description = "Kubernetes DNS service IP."
  type        = string
  default     = "10.20.0.10"
}

# ============================================================
# ACR
# ============================================================

variable "acr_sku" {
  description = "Azure Container Registry SKU."
  type        = string

  validation {
    condition = contains(
      ["Basic", "Standard", "Premium"],
      var.acr_sku
    )

    error_message = "ACR SKU must be Basic, Standard, or Premium."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the ACR public endpoint is enabled."
  type        = bool
  default     = true
}

# ============================================================
# NETWORKING
# ============================================================

variable "vnet_address_space" {
  description = "HomeEase VNet address space."
  type        = list(string)
}

variable "aks_subnet_prefix" {
  description = "AKS subnet address prefixes."
  type        = list(string)
}

variable "private_endpoint_subnet_prefix" {
  description = "Private Endpoint subnet address prefixes."
  type        = list(string)
}

# ============================================================
# KEY VAULT
# ============================================================



variable "keyvault_sku" {
  description = "Key Vault SKU."
  type        = string
  default     = "standard"

  validation {
    condition = contains(
      ["standard", "premium"],
      var.keyvault_sku
    )

    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "keyvault_public_network_access_enabled" {
  description = "Whether public network access to Key Vault is enabled."
  type        = bool
  default     = true
}

# ============================================================
# WORKLOAD IDENTITY
# ============================================================

variable "kubernetes_namespace" {
  description = "Kubernetes namespace used by HomeEase."
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account used by HomeEase."
  type        = string
}


variable "admin_object_id" {
  description = "Azure AD object ID of the admin managing Key Vault secrets manually."
  type        = string
}

# ============================================================
# CI IDENTITY (see ci.tf) — Azure DevOps + GitHub Actions federation
# ============================================================

variable "ado_organization_id" {
  description = <<-EOT
    Azure DevOps ORGANIZATION ID (a GUID), not the org name.
    Find it at: https://dev.azure.com/<org>/_apis/connectionData
    -> instanceId.
  EOT
  type        = string
  default     = null
}

variable "ado_organization_name" {
  description = "Azure DevOps organization name."
  type        = string
  default     = null
}

variable "ado_project_name" {
  description = "Azure DevOps project name."
  type        = string
  default     = null
}

variable "tfstate_storage_account_id" {
  description = "Resource ID of the bootstrap Terraform state storage account. Grants the CI identity Storage Blob Data Contributor so it can plan/apply this environment from GitHub Actions."
  type        = string
  default     = null
}

# ============================================================
# COST GUARDRAIL (see ci.tf)
# ============================================================

variable "monthly_budget_amount" {
  description = "Monthly budget in the billing currency for this environment's resource group."
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "Budget start date. Must be the first of a month, RFC3339, e.g. 2026-10-01T00:00:00Z."
  type        = string
}

variable "budget_contact_emails" {
  description = "Who receives budget alerts."
  type        = list(string)
}