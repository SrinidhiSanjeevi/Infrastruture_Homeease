resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  dns_prefix         = var.dns_prefix
  kubernetes_version = var.kubernetes_version
  sku_tier           = var.sku_tier

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ==========================================================
  # AKS SYSTEM NODE POOL
  # ==========================================================

  default_node_pool {
    name                        = "default"
    vm_size                     = var.vm_size
    vnet_subnet_id              = var.subnet_id
    temporary_name_for_rotation = "tmpdefault"

    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 3

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  # ==========================================================
  # AKS NETWORKING
  # ==========================================================

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"

    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip

    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  role_based_access_control_enabled = true

  # ==========================================================
  # KEY VAULT CSI DRIVER
  # ==========================================================

  key_vault_secrets_provider {
    secret_rotation_enabled  = var.secret_rotation_enabled
    secret_rotation_interval = var.secret_rotation_interval
  }

  tags = var.tags
}

# ============================================================
# AKS -> ACR Pull Permission
# ============================================================

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"

  principal_id = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}