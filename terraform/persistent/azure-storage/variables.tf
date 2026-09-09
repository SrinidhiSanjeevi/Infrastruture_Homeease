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