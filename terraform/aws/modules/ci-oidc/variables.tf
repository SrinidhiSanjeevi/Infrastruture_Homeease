variable "github_owner" {
  description = "GitHub organisation or username, e.g. SrinidhiSanjeevi."
  type        = string
}

variable "github_repository" {
  description = "Repository name, e.g. app_Homeease."
  type        = string
}

variable "allowed_branches" {
  description = "Branches whose workflows may assume the PUSH role. Keep this to main."
  type        = list(string)
  default     = ["main"]
}

variable "allowed_environments" {
  description = "GitHub Environment names whose workflows may assume the push role. Environments can require reviewer approval before the OIDC token is issued, which is the cleanest way to gate privileged CI."
  type        = list(string)
  default     = []
}

variable "allow_tags" {
  description = "Also trust refs/tags/*. Enable only if you cut releases from tags."
  type        = bool
  default     = false
}

variable "create_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. Exactly one stack per AWS account should do this."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an already-existing GitHub OIDC provider, used when create_oidc_provider = false."
  type        = string
  default     = null
}

variable "push_role_name" {
  description = "Name of the CI push role."
  type        = string
  default     = "homeease-ci-ecr-push"
}

variable "ecr_repository_arns" {
  description = "Exact ECR repository ARNs the role may push to. Pass module.ecr.repository_arns values — never [\"*\"]."
  type        = list(string)
}

variable "create_read_role" {
  description = "Create a separate read-only role for pull_request workflows."
  type        = bool
  default     = true
}

variable "ci_secret_names" {
  description = "Names of pre-existing Secrets Manager secrets the pipeline may read (e.g. sonar token). Values are set out of band, never in Terraform."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to IAM resources."
  type        = map(string)
  default     = {}
}
