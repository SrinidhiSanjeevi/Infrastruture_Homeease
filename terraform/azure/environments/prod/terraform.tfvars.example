environment = "prod"

project_name = "homeease"

location = "Central India"

# ============================================================
# AKS
# ============================================================

aks_node_count = 2

aks_vm_size = "Standard_D2s_v5"

# Paid tier provides SLA.
aks_sku_tier = "Standard"

# ============================================================
# ACR
# ============================================================

acr_sku = "Premium"

# Still public in current architecture.
# Later change to false + Private Endpoint.
public_network_access_enabled = true

# ============================================================
# NETWORK
# ============================================================

vnet_address_space = [
  "10.30.0.0/16"
]

aks_subnet_prefix = [
  "10.30.0.0/22"
]

private_endpoint_subnet_prefix = [
  "10.30.4.0/24"
]

tenant_id = "YOUR-AZURE-TENANT-ID"

kubernetes_namespace = "homeease"

service_account_name = "homeease"