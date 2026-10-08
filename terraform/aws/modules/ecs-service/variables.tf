variable "name" {
  description = "Service name — backend, admin-backend, frontend, admin-frontend, or payment-service."
  type        = string
}

variable "environment" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets — Fargate tasks never get a public IP; the ALB (public subnets) is the only public-facing thing."
  type        = list(string)
}

variable "service_connect_namespace_arn" {
  type = string
}

variable "image" {
  description = "Full ECR image URI including tag, e.g. <acct>.dkr.ecr.ap-south-1.amazonaws.com/homeease/backend:<sha>."
  type        = string
}

variable "container_port" {
  type = number
}

variable "health_check_path" {
  description = "HTTP path the container health check calls on 127.0.0.1:container_port. Backends serve /health/live, the nginx frontends serve /health."
  type        = string
  default     = "/health/live"
}

variable "cpu" {
  description = "Fargate task-level vCPU units (256 = 0.25 vCPU). Must be a valid Fargate CPU/memory pair."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task-level memory in MiB."
  type        = number
  default     = 512
}

variable "execution_role_arn" {
  description = "Task execution role — pulls the image, writes logs, injects secrets. Created once in environments/fargate-dev/main.tf, not by this module, so backend/admin-backend/frontend/admin-frontend can share one while payment-service gets its own (mirrors the workload-identity/IRSA split on the other two clouds)."
  type        = string
}

variable "environment_variables" {
  description = "Plain (non-secret) container env vars."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of env-var-name -> Secrets Manager secret ARN, injected at container start."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  description = "Matches this service's HPA maxReplicas in gitops_homeease's charts/<service>/values.yaml."
  type        = number
  default     = 3
}

variable "cpu_target_percent" {
  description = "Matches this service's HPA cpuTargetPercent in gitops_homeease."
  type        = number
  default     = 70
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
  type    = number
  default = 0
}

# INGRESS — exactly one of these describes how this service is reachable

variable "attach_alb" {
  description = "True for frontend/admin-frontend only — the two services with a public Ingress in gitops_homeease. A literal bool, not derived from alb_security_group_id itself, because that value is unknown at plan time (the ALB is created in the same apply) and for_each/count can't branch on an unknown value."
  type        = bool
  default     = false
}

variable "alb_security_group_id" {
  description = "Set together with attach_alb = true. Null for internal-only services."
  type        = string
  default     = null
}

variable "alb_target_group_arn" {
  description = "Set together with alb_security_group_id."
  type        = string
  default     = null
}

variable "allowed_source_security_group_ids" {
  description = "Security groups of the services allowed to call this one directly, keyed by peer service name (not SG id) — the id is only known after apply, and for_each needs its keys known at plan time. E.g. payment-service sets this to { backend = <backend's SG id> } only, mirroring its NetworkPolicy's podSelector.matchLabels restriction to backend alone."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "alarm_topic_arn" {
  description = "SNS topic notified when this service's CPU/memory alarms change state. Null = alarms exist but notify nobody."
  type        = string
  default     = null
}
