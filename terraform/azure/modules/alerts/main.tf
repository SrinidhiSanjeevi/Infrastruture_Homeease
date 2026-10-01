# Alerting baseline: one e-mail action group and metric alerts on the AKS nodes.

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  short_name          = substr(replace("ag${var.name_prefix}", "-", ""), 0, 12)

  dynamic "email_receiver" {
    for_each = toset(var.email_addresses)
    content {
      name          = "email-${index(var.email_addresses, email_receiver.value)}"
      email_address = email_receiver.value
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "node_cpu" {
  name                = "alert-${var.name_prefix}-node-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_id]
  description         = "AKS node CPU above ${var.cpu_threshold_percent}% for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_threshold_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "node_memory" {
  name                = "alert-${var.name_prefix}-node-memory"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_id]
  description         = "AKS node memory above ${var.memory_threshold_percent}% for 15 minutes."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.memory_threshold_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = var.tags
}
