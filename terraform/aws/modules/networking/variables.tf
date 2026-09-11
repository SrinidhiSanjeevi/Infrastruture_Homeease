variable "environment" {
  description = "Environment name, used in resource names/tags."
  type        = string
}

variable "cluster_name" {
  description = "Name the EKS cluster will be created with. Needed here (before the eks module runs) only for the kubernetes.io/cluster/<name> subnet tags the AWS Load Balancer controller and VPC CNI use to auto-discover subnets — this module never creates the cluster itself."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per AZ used."
  type        = list(string)
  default     = ["10.20.0.0/20", "10.20.16.0/20"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private (EKS node) subnets, one per AZ used."
  type        = list(string)
  default     = ["10.20.128.0/20", "10.20.144.0/20"]
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
