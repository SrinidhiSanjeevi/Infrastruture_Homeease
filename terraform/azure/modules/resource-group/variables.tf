variable "name" {
  description = "Name of the application resource group."
  type        = string
}

variable "location" {
  description = "Azure region for the application resource group."
  type        = string
}

variable "tags" {
  description = "Tags applied to the resource group."
  type        = map(string)
}