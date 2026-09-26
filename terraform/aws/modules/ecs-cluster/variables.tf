variable "cluster_name" {
  type = string
}

variable "namespace_name" {
  description = "Service Connect / Cloud Map namespace. Services register under <service>.<namespace_name>."
  type        = string
}

variable "spot_weight" {
  type    = number
  default = 3
}

variable "on_demand_weight" {
  type    = number
  default = 1
}

variable "on_demand_base" {
  description = "Minimum tasks that always run on on-demand Fargate before Spot weighting kicks in. 0 for a dev/demo environment — see main.tf for the Spot trade-off reasoning."
  type        = number
  default     = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
