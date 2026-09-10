variable "resource_group_name" {
  description = "Resource group containing the HomeEase workload identity."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "identity_name" {
  description = "Name of the user-assigned managed identity."
  type        = string
}

variable "federated_credential_name" {
  description = "Name of the AKS federated identity credential."
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer URL exposed by the AKS cluster."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace used by HomeEase."
  type        = string
}

variable "service_account_name" {
  description = "Primary Kubernetes service account associated with the workload identity."
  type        = string
}

variable "additional_service_accounts" {
  description = <<-EOT
    Extra (namespace, service_account_name) pairs that should be able
    to federate against this SAME identity — for services that
    deliberately share access, not a general-purpose list. A service
    that needs its own blast radius gets its own module instance
    instead of an entry here.
  EOT
  type = list(object({
    namespace            = string
    service_account_name = string
  }))
  default = []
}

variable "key_vault_id" {
  description = "Resource ID of the HomeEase Azure Key Vault."
  type        = string
}

variable "tags" {
  description = "Tags applied to workload identity resources."
  type        = map(string)
  default     = {}
}


variable "admin_object_id" {
  description = "Object ID of the admin/user who needs read-write access to Key Vault secrets (for manual secret management)."
  type        = string
}

