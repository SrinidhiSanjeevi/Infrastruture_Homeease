variable "role_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "The EKS cluster's OIDC provider ARN (module.eks.oidc_provider_arn) — NOT the GitHub Actions OIDC provider from modules/ci-oidc."
  type        = string
}

variable "oidc_provider_url" {
  description = "The EKS cluster's OIDC issuer host, without the https:// prefix (module.eks.oidc_provider_url)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount this role federates with."
  type        = string
}

variable "service_account_name" {
  type = string
}

variable "additional_service_accounts" {
  description = "Extra (namespace, service_account_name) pairs that may also assume this same role — for services that genuinely share the same access and blast radius. A service that needs its own isolated blast radius gets its own module instance instead of an entry here (see environments/dev/main.tf)."
  type = list(object({
    namespace            = string
    service_account_name = string
  }))
  default = []
}

variable "secret_arns" {
  description = "Secrets Manager ARNs this role may read. Empty list grants no Secrets Manager access at all."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
