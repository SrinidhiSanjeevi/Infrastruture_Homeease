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
  description = "Monthly budget ceiling in USD. NOTE: once module.eks/module.networking are applied, actual spend is ~$135/month baseline (EKS control plane + 1 NAT Gateway + 1 t3.medium node) before any autoscaling — the historical default of \"50\" below is registry-only sizing and will alert immediately once EKS exists."
  type        = string
  default     = "150"
}

variable "budget_contact_emails" {
  description = "Who receives budget alerts."
  type        = list(string)
}

# ============================================================
# NETWORKING
# ============================================================

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.0.0/20", "10.20.16.0/20"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.128.0/20", "10.20.144.0/20"]
}

# ============================================================
# EKS
# ============================================================

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

# ============================================================
# KUBERNETES / IRSA
# ============================================================

variable "kubernetes_namespace" {
  description = "Namespace payment-service's ServiceAccount lives in — must match apps/payment-service/overlays/aws/<env>/ in gitops_homeease exactly, or IRSA's trust policy will reject the pod's token."
  type        = string
  default     = "homeease-dev"
}

variable "payment_secret_names" {
  description = "Secrets Manager secret name suffixes created under homeease/<environment>/payment-service/."
  type        = list(string)
  default     = ["razorpay-key-id", "razorpay-key-secret", "razorpay-webhook-secret"]
}
