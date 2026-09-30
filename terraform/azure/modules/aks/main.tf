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

  # Security patches land automatically instead of waiting for a human.
  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = "NodeImage"

  # Removes stale, vulnerable images from nodes.
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  # Built-in Azure Policy add-on (pod security baselines via Gatekeeper).
  azure_policy_enabled = true

  # true = the shared static admin kubeconfig is disabled; requires
  # admin_group_object_ids so people sign in with Entra ID instead.
  local_account_disabled = var.local_account_disabled

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

  # Entra ID sign-in + Azure RBAC for Kubernetes (off until a group is given).
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = length(var.admin_group_object_ids) > 0 ? [1] : []
    content {
      azure_rbac_enabled     = true
      admin_group_object_ids = var.admin_group_object_ids
    }
  }

  # Restrict who can reach the API server (off until CIDRs are given).
  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # Container Insights (metrics + container logs).
  dynamic "oms_agent" {
    for_each = var.enable_diagnostics ? [1] : []
    content {
      log_analytics_workspace_id      = var.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

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

# Audit trail: Kubernetes API audit (who ran kubectl what) and auth events.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "guard"
  }
}

resource "azurerm_management_lock" "this" {
  count = var.enable_delete_lock ? 1 : 0

  name       = "lock-${var.name}"
  scope      = azurerm_kubernetes_cluster.this.id
  lock_level = "CanNotDelete"
  notes      = "Production cluster. Remove the lock deliberately before deleting."
}
