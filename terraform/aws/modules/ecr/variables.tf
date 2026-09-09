variable "namespace" {
  description = "Repository path prefix, e.g. 'homeease' -> homeease/backend."
  type        = string
  default     = "homeease"
}

variable "services" {
  description = "Service names. One ECR repository is created per entry."
  type        = list(string)
  default     = ["backend", "admin-backend", "frontend", "payment-service"]
}

variable "retained_image_count" {
  description = "How many tagged images to keep per repository before expiring the oldest."
  type        = number
  default     = 15
}

variable "force_delete" {
  description = "Allow terraform destroy to remove repositories that still contain images. Convenient on a trial account; set false for anything real."
  type        = bool
  default     = true
}

variable "pull_principal_arns" {
  description = "IAM principals allowed to pull (typically the EKS node role ARN). Null skips the repository policy."
  type        = list(string)
  default     = null
}

variable "manage_registry_scanning" {
  description = "Manage the account-wide registry scanning configuration. Set true in exactly ONE environment per AWS account — it is a registry-level, not repository-level, setting, so multiple environments would fight over it."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every repository."
  type        = map(string)
  default     = {}
}
