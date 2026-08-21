variable "name" {
  description = "AKS cluster name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the AKS cluster."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version. Null uses the Azure-supported default."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "AKS pricing tier."
  type        = string

  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "AKS SKU tier must be Free or Standard."
  }
}

variable "node_count" {
  description = "Number of nodes in the default system node pool."
  type        = number

  validation {
    condition     = var.node_count >= 1
    error_message = "Node count must be at least 1."
  }
}

variable "vm_size" {
  description = "VM size for the default node pool."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the AKS node pool."
  type        = string
}

variable "service_cidr" {
  description = "Kubernetes service CIDR."
  type        = string
}

variable "dns_service_ip" {
  description = "Kubernetes DNS service IP."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the ACR that AKS should pull from."
  type        = string
}

variable "tags" {
  description = "Tags applied to the AKS cluster."
  type        = map(string)
  default     = {}
}