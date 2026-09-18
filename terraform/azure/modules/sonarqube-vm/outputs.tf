output "public_ip" {
  value = azurerm_public_ip.sonarqube.ip_address
}

output "fqdn" {
  description = "The hostname SonarQube is reachable at over HTTPS — use this as the SonarQube service connection URL in Azure DevOps."
  value       = local.fqdn
}

output "vm_id" {
  value = azurerm_linux_virtual_machine.sonarqube.id
}

output "backup_storage_account_name" {
  value = azurerm_storage_account.backup.name
}

output "backup_container_name" {
  value = azurerm_storage_container.backups.name
}
