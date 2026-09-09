variable "key_vault_id" {
  description = "Resource ID of the Key Vault to write secrets into."
  type        = string
}

variable "mongo_uri" {
  type      = string
  sensitive = true
}

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "email_user" {
  type = string
}

variable "email_pass" {
  type      = string
  sensitive = true
}

variable "razorpay_key_id" {
  type = string
}

variable "razorpay_key_secret" {
  type      = string
  sensitive = true
}