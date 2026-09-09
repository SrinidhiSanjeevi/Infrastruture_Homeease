variable "region" {
  description = "AWS region. ap-south-1 (Mumbai) is the closest match to the Central India Azure region used elsewhere in this repo."
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "github_owner" {
  description = "GitHub organisation or username that owns the app repository."
  type        = string
  default     = "SrinidhiSanjeevi"
}

variable "github_repository" {
  description = "App repository name — the one whose GitHub Actions workflow pushes images to ECR."
  type        = string
  default     = "app_Homeease"
}

variable "infra_github_owner" {
  description = "GitHub organisation or username that owns the infra repository (the one whose workflow applies this Terraform stack)."
  type        = string
  default     = "SrinidhiSanjeevi"
}

variable "infra_github_repository" {
  description = "Infra repository name (Infrastruture_Homeease)."
  type        = string
  default     = "Infrastruture_Homeease"
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
