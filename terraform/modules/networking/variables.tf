variable "resource_group_name" {
  description = "Resource group containing the networking resources."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "environment" {
  description = "Environment name used for resource naming."
  type        = string

  validation {
    condition = contains(
      ["dev", "test", "prod"],
      var.environment
    )

    error_message = "Environment must be dev, test, or prod."
  }
}

variable "vnet_address_space" {
  description = "Address space assigned to the HomeEase virtual network."
  type        = list(string)
}

variable "aks_subnet_prefix" {
  description = "Address prefixes assigned to the AKS subnet."
  type        = list(string)
}

variable "private_endpoint_subnet_prefix" {
  description = "Address prefixes reserved for Azure Private Endpoints."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to networking resources."
  type        = map(string)
  default     = {}
}