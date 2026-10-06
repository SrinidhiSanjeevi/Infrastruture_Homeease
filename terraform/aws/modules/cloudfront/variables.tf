variable "environment" {
  type = string
}

variable "alb_dns_name" {
  description = "DNS name of the public ALB used as the origin."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
