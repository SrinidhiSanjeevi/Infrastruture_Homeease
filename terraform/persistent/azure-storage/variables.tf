variable "location" {
  description = "Azure region for persistent HomeEase image storage."
  type        = string
  default     = "Central India"
}

variable "project_name" {
  description = "HomeEase project name."
  type        = string
  default     = "homeease"
}

variable "storage_account_name" {
  description = "Globally unique Azure Storage Account name."
  type        = string
}

variable "workload_identity_name" {
  description = "Name of the app's user-assigned managed identity (created by environments/dev). Looked up by name so a rebuilt identity never leaves a stale, hard-coded principal ID behind."
  type        = string
  default     = "id-homeease-app-dev"
}

variable "workload_identity_resource_group_name" {
  description = "Resource group that holds the workload identity."
  type        = string
  default     = "rg-homeease-dev"
}

variable "workload_identity_principal_id" {
  description = "Optional override for the identity's principal (object) ID. Leave null to look it up by name."
  type        = string
  default     = null
}
