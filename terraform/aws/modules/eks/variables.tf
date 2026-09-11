variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane."
  type        = string
  default     = "1.31"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs — where nodes run."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs — added to the cluster's own vpc_config so control-plane ENIs can use them too; nodes never run here."
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
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

variable "enable_network_policy" {
  description = "Turn on the VPC CNI's NetworkPolicy enforcement (ENABLE_NETWORK_POLICY=true). Required for apps/*/base/networkpolicy.yaml in gitops_homeease to actually do anything on this cluster."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
