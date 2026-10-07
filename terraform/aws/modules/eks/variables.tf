variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane. null = let EKS pick its current default (recommended: an old pinned version drops into paid extended support). Pin it once the cluster exists."
  type        = string
  default     = null
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
  description = "EC2 instance types for the managed node group. 8 GiB minimum: the monitoring stack plus six services plus Argo CD do not fit on 4 GiB. m7i-flex.large (2 vCPU, 8 GiB) because this account is on the AWS Free Plan, which refuses every other 8 GiB type (t3.large fails with 'not eligible for Free Tier'). On a paid plan, t3.large is cheaper."
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is roughly 70% cheaper but nodes can be reclaimed with two minutes' notice - do not use it on the day of a demo."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_ami_type" {
  description = "Node AMI family. AL2 is end-of-life on current Kubernetes versions."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
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

variable "enable_prefix_delegation" {
  description = "VPC CNI prefix delegation: raises the pod limit per node (t3.large: 35 -> 110). Without it Argo CD + monitoring + the six services run out of pod IPs."
  type        = bool
  default     = true
}

variable "ecr_repository_arns" {
  description = "ECR repositories the nodes may pull from. Scoped identity policy on the node role instead of the account-wide AmazonEC2ContainerRegistryReadOnly."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Authentication is still required; narrow this to your own egress IPs to harden it."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bootstrap_creator_admin" {
  description = "Give whoever runs terraform apply implicit cluster-admin. Turn off when access entries are declared explicitly, so access does not depend on who happened to apply (a CI role and a laptop user would otherwise get different access)."
  type        = bool
  default     = true
}
