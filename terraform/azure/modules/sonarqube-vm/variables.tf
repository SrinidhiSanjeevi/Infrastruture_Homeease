variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "vnet_name" {
  description = "Existing VNet (from module.networking) to add the tools subnet to. This module does not create its own VNet."
  type        = string
}

variable "tools_subnet_prefix" {
  description = "CIDR for the new subnet this module creates inside the existing VNet."
  type        = list(string)
  default     = ["10.10.8.0/28"]
}

variable "vm_size" {
  description = "SonarQube (Community, bundled Elasticsearch) needs at least 2GB free RAM beyond the OS — Standard_B2s (2 vCPU / 4GB) is the practical minimum, not Standard_B1s (1GB, will fail to start)."
  type        = string
  default     = "Standard_B2s"
}

variable "data_disk_size_gb" {
  description = "Managed disk holding /data (SonarQube data/extensions/logs + Postgres data). Separate from the OS disk so VM/OS-disk replacement never touches this."
  type        = number
  default     = 32
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Your SSH public key content (e.g. contents of ~/.ssh/id_rsa.pub). Never a private key. No default — you must supply this."
  type        = string
}

variable "admin_ssh_source_cidr" {
  description = "CIDR allowed to reach port 22. Use your own IP/32 (curl ifconfig.me). Never 0.0.0.0/0 or \"*\"."
  type        = string
}

variable "dns_label" {
  description = "Hostname the VM is reachable at. Default: the nip.io wildcard DNS trick, which resolves \"<ip>.nip.io\" to <ip> with zero DNS setup — Caddy gets a real Let's Encrypt cert for it because it's a real (if ugly) public hostname. Set to a real domain you own once you have one; nothing else in this module needs to change."
  type        = string
  default     = null
}

variable "backup_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
