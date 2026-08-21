environment  = "dev"
project_name = "homeease"

location = "Central India"

# ============================================================
# AKS
# ============================================================

aks_node_count = 1

aks_vm_size = "Standard_D2s_v5"

aks_sku_tier = "Free"

# Let Azure select the supported default.
kubernetes_version = null

# Kubernetes networking
service_cidr   = "10.20.0.0/16"
dns_service_ip = "10.20.0.10"

# ============================================================
# ACR
# ============================================================

# Basic keeps development cost lower.
acr_sku = "Basic"

# Public endpoint is intentional for the current
# Azure DevOps architecture.
public_network_access_enabled = true

# ============================================================
# NETWORK
# ============================================================

vnet_address_space = [
  "10.10.0.0/16"
]

aks_subnet_prefix = [
  "10.10.0.0/22"
]

private_endpoint_subnet_prefix = [
  "10.10.4.0/24"
]

# ============================================================
# KEY VAULT
# ============================================================

tenant_id = "YOUR-AZURE-TENANT-ID"

keyvault_sku = "standard"

keyvault_public_network_access_enabled = true

# ============================================================
# WORKLOAD IDENTITY
# ============================================================

kubernetes_namespace = "homeease"

service_account_name = "homeease"