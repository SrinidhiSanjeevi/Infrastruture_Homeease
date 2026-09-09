variable "environment" {
  description = "Environment name (staging or prod)."
  type        = string
}

variable "account_id" {
  description = "AWS account ID, used to scope the budgets permission."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider already created by the dev environment's ci-oidc module."
  type        = string
}

variable "github_owner" {
  description = "GitHub organisation or username that owns the infra repository."
  type        = string
}

variable "github_repository" {
  description = "Infra repository name (Infrastruture_Homeease)."
  type        = string
}

variable "allowed_branches" {
  description = "Branches whose Terraform-apply workflow runs may assume this role."
  type        = list(string)
  default     = ["main"]
}

variable "tags" {
  description = "Tags applied to the IAM role."
  type        = map(string)
  default     = {}
}
