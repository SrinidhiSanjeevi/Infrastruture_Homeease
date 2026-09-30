variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "acr_name" {
  description = "Name of the environment's container registry (created by environments/dev)."
  type        = string
  default     = "acrhomeeasedev01"
}

variable "tfstate_storage_account_id" {
  description = "Resource ID of the Terraform state storage account."
  type        = string
  default     = null
}

variable "github_owner" {
  description = "GitHub account that owns the app repository."
  type        = string
  default     = "SrinidhiSanjeevi"
}

variable "github_repository" {
  description = "GitHub repository whose workflows authenticate with this identity."
  type        = string
  default     = "Infrastruture_Homeease"
}

variable "enable_azure_devops" {
  description = "Create the Azure DevOps federated credential (needs the real org GUID)."
  type        = bool
  default     = false
}

variable "ado_organization_id" {
  description = "Azure DevOps organization GUID."
  type        = string
  default     = null
}

variable "ado_organization_name" {
  description = "Azure DevOps organization name."
  type        = string
  default     = null
}

variable "ado_project_name" {
  description = "Azure DevOps project name."
  type        = string
  default     = null
}
