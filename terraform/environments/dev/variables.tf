variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition = contains(
      ["dev", "test", "prod"],
      var.environment
    )

    error_message = "Environment must be dev, test, or prod."
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


variable "mongo_uri" {
  type      = string
  sensitive = true
}

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "email_user" {
  type = string
}

variable "email_pass" {
  type      = string
  sensitive = true
}

variable "razorpay_key_id" {
  type = string
}

variable "razorpay_key_secret" {
  type      = string
  sensitive = true
}