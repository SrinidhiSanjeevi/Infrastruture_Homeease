variable "region" {
  description = "AWS region. ap-south-1 (Mumbai) is the closest match to the Central India Azure region used elsewhere in this repo."
  type        = string
  default     = "ap-south-1"
}

variable "bucket_prefix" {
  description = "Prefix for the generated, globally-unique state bucket name."
  type        = string
  default     = "tfstate-homeease-aws"
}

variable "tags" {
  description = "Tags applied to the state bucket."
  type        = map(string)
  default = {
    project    = "homeease"
    managed_by = "terraform"
    component  = "bootstrap"
  }
}
