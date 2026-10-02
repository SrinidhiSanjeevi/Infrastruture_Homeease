variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  description = "Tag/naming value shared with environments/dev (the registry stack this builds on) — NOT this directory's name. Both stacks describe the same logical 'dev' environment; fargate-dev is which STACK, not which environment."
  type        = string
  default     = "dev"
}

variable "registry_state_bucket" {
  description = "Same bucket as environments/dev/backend.tf — paste the bootstrap stack's bucket_name output here too."
  type        = string
}

variable "registry_state_key" {
  type    = string
  default = "aws/dev.terraform.tfstate"
}

variable "infra_github_owner" {
  type    = string
  default = "SrinidhiSanjeevi"
}

variable "infra_github_repository" {
  type    = string
  default = "Infrastruture_Homeease"
}

variable "monthly_budget_amount" {
  description = "This stack's own budget, separate from environments/dev's. Rough estimate at the default sizing (5 services, 1-2 tasks each, mostly Spot, 1 ALB, shared NAT already paid for by environments/dev): ~$45-60/month. See this environment's README for the line-item breakdown."
  type        = string
  default     = "70"
}

variable "budget_contact_emails" {
  type = list(string)
}

# ============================================================
# IMAGE TAGS — the "GitOps" file. app_Homeease's aws-ci.yml commits
# updates here after a successful push+sign to ECR, one file, same
# mechanism azure-pipelines.yml's Promote stage already uses against
# gitops_homeease's values-azure-dev.yaml. Loaded automatically
# (.auto.tfvars — no -var-file flag needed) from image-tags.auto.tfvars
# in this directory.
# ============================================================

variable "image_tags" {
  type = object({
    backend         = string
    admin_backend   = string
    frontend        = string
    admin_frontend  = string
    payment_service = string
  })
}

# ============================================================
# NON-SECRET APP CONFIG — the direct equivalent of each chart's plain
# `env:` block in gitops_homeease (as opposed to secrets, which come
# from Secrets Manager via environments/dev's outputs).
# ============================================================

variable "allowed_origins" {
  description = "CORS origin(s) — set once the ALB DNS name is known from a first apply, or a real domain if one exists."
  type        = string
  default     = "*"
}

variable "container_insights" {
  description = "CloudWatch Container Insights for the ECS cluster (per-service CPU/memory/task graphs)."
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN to enable HTTPS on the ALB (port 443, with :80 redirecting). Leave null until a domain and certificate exist."
  type        = string
  default     = null
}

variable "azure_storage_account_name" {
  description = "Azure Storage account holding service/professional images (persistent/azure-storage output storage_account_name)."
  type        = string
  default     = "sthomeeaseimgayhiue"
}

variable "notification_image_tag" {
  description = "Tag of homeease/notification-service in ECR. Pushed by hand (not part of aws-ci.yml yet)."
  type        = string
  default     = "v1"
}
