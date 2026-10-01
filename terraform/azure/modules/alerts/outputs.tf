output "action_group_id" {
  description = "Resource ID of the e-mail action group (reuse it for further alerts)."
  value       = azurerm_monitor_action_group.this.id
}
