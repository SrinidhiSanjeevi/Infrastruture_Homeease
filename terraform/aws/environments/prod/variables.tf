variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "github_owner" {
  description = "GitHub organisation or username that owns the infra repository."
  type        = string
  default     = "SrinidhiSanjeevi"
}

variable "github_repository" {
  description = "Infra repository name — the one whose GitHub Actions workflow applies Terraform."
  type        = string
  default     = "Infrastruture_Homeease"
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider created by the dev environment's ci-oidc module. Run `terraform output oidc_provider_arn` in aws/environments/dev and paste it here."
  type        = string
}

variable "monthly_budget_amount" {
  description = "Monthly budget ceiling in USD."
  type        = string
  default     = "50"
}

variable "budget_contact_emails" {
  description = "Who receives budget alerts."
  type        = list(string)
}
