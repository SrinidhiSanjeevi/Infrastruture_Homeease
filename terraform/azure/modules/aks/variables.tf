variable "name" {
  description = "AKS cluster name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the AKS cluster."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version. Null uses the Azure-supported default."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "AKS pricing tier."
  type        = string

  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "AKS SKU tier must be Free or Standard."
  }
}

variable "node_count" {
  description = "Number of nodes in the default system node pool."
  type        = number

  validation {
    condition     = var.node_count >= 1
    error_message = "Node count must be at least 1."
  }
}

variable "vm_size" {
  description = "VM size for the default node pool."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the AKS node pool."
  type        = string
}

variable "service_cidr" {
  description = "Kubernetes service CIDR."
  type        = string
}

variable "dns_service_ip" {
  description = "Kubernetes DNS service IP."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the ACR that AKS should pull from."
  type        = string
}

variable "tags" {
  description = "Tags applied to the AKS cluster."
  type        = map(string)
  default     = {}
}

variable "secret_rotation_enabled" {
  description = "Whether the Key Vault CSI driver polls for and syncs rotated secrets."
  type        = bool
  default     = true
}

variable "secret_rotation_interval" {
  description = "How often the CSI driver polls Key Vault for secret changes."
  type        = string
  default     = "2m"
}

variable "enable_diagnostics" {
  description = "Send audit logs to Log Analytics. A plain bool (not a null check) because the workspace ID is unknown at plan time."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace that receives diagnostics."
  type        = string
  default     = null
}

variable "enable_delete_lock" {
  description = "Apply a CanNotDelete management lock."
  type        = bool
  default     = false
}

variable "automatic_upgrade_channel" {
  description = "AKS auto-upgrade channel: patch, stable, rapid, node-image or none."
  type        = string
  default     = "patch"
}

variable "local_account_disabled" {
  description = "Disable the static admin kubeconfig. Only set true together with admin_group_object_ids."
  type        = bool
  default     = false
}

variable "admin_group_object_ids" {
  description = "Entra ID groups with cluster-admin. Non-empty enables Entra ID + Azure RBAC."
  type        = list(string)
  default     = []
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the Kubernetes API. Empty = open (unchanged behaviour)."
  type        = list(string)
  default     = []
}

variable "enable_container_insights" {
  description = "Enable the Container Insights (oms_agent) add-on. Off on small clusters that already run Prometheus/Loki."
  type        = bool
  default     = true
}

variable "image_cleaner_enabled" {
  description = "Enable the AKS image cleaner (eraser). Off on small clusters where its CPU requests starve workloads."
  type        = bool
  default     = true
}
