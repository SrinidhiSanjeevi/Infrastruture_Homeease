variable "name" {
  description = "Globally unique Azure Key Vault name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the Key Vault."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID."
  type        = string
}

variable "sku_name" {
  description = "Key Vault SKU."
  type        = string
  default     = "standard"

  validation {
    condition = contains(
      ["standard", "premium"],
      var.sku_name
    )

    error_message = "sku_name must be standard or premium."
  }
}

variable "public_network_access_enabled" {
  description = "Whether public network access to Key Vault is enabled."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the Key Vault."
  type        = map(string)
  default     = {}
}

variable "enable_diagnostics" {
  description = "Send audit logs to Log Analytics. A plain bool (not a null check) because the workspace ID is unknown at plan time."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace that receives diagnostics."
  type        = string
  default     = null
}

variable "enable_delete_lock" {
  description = "Apply a CanNotDelete management lock."
  type        = bool
  default     = false
}

variable "network_acls" {
  description = "Key Vault firewall. null = no firewall block (unchanged behaviour)."
  type = object({
    default_action             = string
    bypass                     = optional(string, "AzureServices")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null
}
