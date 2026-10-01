variable "name_prefix" {
  description = "Prefix for alert resource names, e.g. homeease-dev."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the alert resources."
  type        = string
}

variable "aks_id" {
  description = "Resource ID of the AKS cluster to watch."
  type        = string
}

variable "email_addresses" {
  description = "E-mail addresses that receive alerts."
  type        = list(string)
}

variable "cpu_threshold_percent" {
  description = "Node CPU alert threshold."
  type        = number
  default     = 80
}

variable "memory_threshold_percent" {
  description = "Node memory alert threshold."
  type        = number
  default     = 80
}

variable "tags" {
  description = "Tags applied to the alert resources."
  type        = map(string)
  default     = {}
}
