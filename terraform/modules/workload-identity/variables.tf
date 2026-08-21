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
  description = "Kubernetes service account associated with the workload identity."
  type        = string
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