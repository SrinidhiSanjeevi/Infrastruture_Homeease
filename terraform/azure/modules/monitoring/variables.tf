variable "name" {
  description = "Log Analytics workspace name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the workspace."
  type        = string
}

variable "retention_in_days" {
  description = "How long logs are kept (30 is the free-included minimum)."
  type        = number
  default     = 30
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB (cost guardrail)."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags applied to the workspace."
  type        = map(string)
  default     = {}
}
