# Central Log Analytics workspace: receives audit/diagnostic logs from
# ACR, Key Vault and AKS so "who touched what" is answerable after the fact.

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku               = "PerGB2018"
  retention_in_days = var.retention_in_days

  # Hard ceiling on ingestion so a noisy cluster cannot run up the bill.
  daily_quota_gb = var.daily_quota_gb

  tags = var.tags
}
