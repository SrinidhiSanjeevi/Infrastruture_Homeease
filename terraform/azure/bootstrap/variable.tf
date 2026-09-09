variable "resource_group_name" {
  description = "Resource group that contains Terraform remote state resources."
  type        = string
  default     = "tfstate-rg"
}

variable "location" {
  description = "Azure region for Terraform state infrastructure."
  type        = string
  default     = "centralindia"
}

variable "storage_account_prefix" {
  description = "Globally unique storage account name prefix."
  type        = string
  default     = "tfstatehomeease"

  validation {
    condition     = length(var.storage_account_prefix) <= 18
    error_message = "Storage account prefix must be 18 characters or fewer."
  }
}

variable "container_name" {
  description = "Blob container used for Terraform remote state."
  type        = string
  default     = "tfstate"
}

variable "tags" {
  description = "Tags applied to Terraform bootstrap resources."
  type        = map(string)

  default = {
    project    = "homeease"
    purpose    = "terraform-state"
    managed_by = "terraform-bootstrap"
  }
}