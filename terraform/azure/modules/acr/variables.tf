variable "name" {
  description = "Globally unique Azure Container Registry name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "ACR name must contain only letters and numbers and be 5-50 characters long."
  }
}

variable "resource_group_name" {
  description = "Resource group containing the ACR."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku" {
  description = "ACR SKU."
  type        = string
  default     = "Basic"

  validation {
    condition = contains(
      ["Basic", "Standard", "Premium"],
      var.sku
    )

    error_message = "ACR SKU must be Basic, Standard, or Premium."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the public ACR endpoint is enabled. Keep enabled until Azure DevOps uses a VNet-connected agent."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the ACR."
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

variable "retention_policy_in_days" {
  description = "Days before untagged manifests are purged (Premium SKU only)."
  type        = number
  default     = 30
}
