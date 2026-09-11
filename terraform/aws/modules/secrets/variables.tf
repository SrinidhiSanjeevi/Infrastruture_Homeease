variable "name_prefix" {
  description = "Path prefix for every secret this instance creates, e.g. \"homeease/dev/payment-service\" -> homeease/dev/payment-service/razorpay-key-id. Must match the objectName values apps/payment-service/overlays/aws/*/secretproviderclass.yaml in gitops_homeease reads."
  type        = string
}

variable "secret_names" {
  description = "Secret name suffixes. One empty Secrets Manager container is created per entry."
  type        = list(string)
}

variable "recovery_window_in_days" {
  type    = number
  default = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
