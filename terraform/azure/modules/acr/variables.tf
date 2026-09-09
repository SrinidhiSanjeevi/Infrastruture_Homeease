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