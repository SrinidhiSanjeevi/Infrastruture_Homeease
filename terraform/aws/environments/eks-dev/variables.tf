variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "registry_state_bucket" {
  description = "S3 bucket holding the dev stack's state (VPC, ECR, Secrets Manager containers, OIDC)."
  type        = string
}

variable "registry_state_key" {
  type    = string
  default = "aws/dev.terraform.tfstate"
}

variable "infra_github_owner" {
  description = "GitHub owner of the infrastructure repo; the apply role trusts workflows from it."
  type        = string
  default     = "SrinidhiSanjeevi"
}

variable "infra_github_repository" {
  type    = string
  default = "Infrastruture_Homeease"
}

variable "kubernetes_namespace" {
  description = "Namespace the application charts deploy into (Argo CD apps use homeease-dev)."
  type        = string
  default     = "homeease-dev"
}

variable "kubernetes_version" {
  description = "null = EKS default. Pin after the first apply."
  type        = string
  default     = null
}

variable "node_instance_types" {
  description = "Free Plan accounts can only launch free-tier-eligible types (see `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true`). m7i-flex.large is the 8 GiB one."
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
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

variable "public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "enable_cloudfront" {
  description = "Two-phase apply. false on the first apply (the ingress NLBs do not exist yet); the workflow flips it to true after scripts/bootstrap-eks.sh has created them, and CloudFront then points at them."
  type        = bool
  default     = false
}

variable "monthly_budget_amount" {
  description = "USD. Sized for the EKS control plane + two t3.large nodes + two NLBs + NAT; see docs/adr/0002."
  type        = number
  default     = 250
}

variable "budget_contact_emails" {
  type = list(string)
}

variable "create_fargate_teardown_role" {
  description = "Opt-in. Creates a BROAD role (PowerUserAccess + scoped IAM) that only the aws-fargate-destroy.yml workflow on main can assume. Needed only for the ECS decommission window; set back to false and apply once the Fargate stack is gone. The alternative is `terraform destroy` run locally with your own credentials (see README)."
  type        = bool
  default     = false
}

variable "cluster_admin_principal_arns" {
  description = "IAM users/roles that get cluster-admin through EKS access entries, in addition to the CI apply role. Declared explicitly so access never depends on who ran the first apply."
  type        = list(string)
  default     = ["arn:aws:iam::226236025590:user/homeease-devops"]
}
