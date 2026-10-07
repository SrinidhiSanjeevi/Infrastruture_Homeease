variable "environment" {
  type = string
}

variable "alb_dns_name" {
  description = "DNS name of the public ALB used as the origin for both distributions (Fargate path). Leave null when both origin names are set below (EKS path)."
  type        = string
  default     = null
}

variable "app_origin_dns_name" {
  description = "Override the customer distribution's origin (EKS: the customer ingress NLB). null = use alb_dns_name."
  type        = string
  default     = null
}

variable "admin_origin_dns_name" {
  description = "Override the admin distribution's origin (EKS: the admin ingress NLB). null = use alb_dns_name."
  type        = string
  default     = null
}

variable "app_origin_port" {
  description = "HTTP port of the customer origin. 80 on both the ALB and the EKS ingress NLB."
  type        = number
  default     = 80
}

variable "admin_origin_port" {
  description = "HTTP port of the admin origin. 8081 on the shared ALB; 80 on the EKS admin ingress NLB."
  type        = number
  default     = 8081
}

variable "tags" {
  type    = map(string)
  default = {}
}
