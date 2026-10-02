variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS on port 443. Null = HTTP only."
  type        = string
  default     = null
}

variable "alarm_topic_arn" {
  description = "SNS topic notified on target-health and 5xx alarms. Null = no notifications."
  type        = string
  default     = null
}
