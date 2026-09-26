# ============================================================
# SonarQube — self-hosted, VM + Docker Compose.
#
# NOT a toy: this is Terraform-managed (IaC, same as every other
# resource in this repo, not clicked together in the Portal),
# zero-touch bootstrapped via cloud-init, backed by a dedicated
# managed data disk (SonarQube data + Postgres data, independent of
# the OS disk's lifecycle), backed up nightly to Blob Storage via the
# VM's own Managed Identity (no stored credentials anywhere), and
# fronted by Caddy for automatic HTTPS. See ../../../../SONARQUBE.md
# for the full persistence/backup/restore story.
#
# Why a VM and not AKS: this cluster's ingress-nginx/cert-manager
# aren't installed yet (see gitops_homeease/platform/README.md), and
# a 1-node dev cluster shouldn't absorb SonarQube's bundled
# Elasticsearch on top of the app workloads it's sized for. A VM is
# also just... simpler to demo and reason about for exactly this one
# admin tool. Revisit once ingress-nginx/cert-manager exist and the
# node pool has headroom.
# ============================================================

data "azurerm_subscription" "current" {}

# ============================================================
# NETWORKING — a new small subnet inside the EXISTING VNet
# (module.networking), not a new VNet. Keeps this VM on the same
# network as AKS without touching the networking module itself.
# ============================================================

resource "azurerm_subnet" "tools" {
  name                 = "snet-tools-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = var.tools_subnet_prefix
}

resource "azurerm_network_security_group" "sonarqube" {
  name                = "nsg-sonarqube-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Required for Let's Encrypt's HTTP-01 challenge and to redirect
  # plain-HTTP hits to HTTPS. Not a bypass of TLS — Caddy answers on
  # :80 only for the ACME challenge and a redirect, nothing else.
  security_rule {
    name                       = "AllowHTTPForACME"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Azure DevOps hosted agents have no fixed, allow-listable IP
  # range — Microsoft explicitly does not publish one. HTTPS from
  # "Internet" above is what makes this reachable from ADO; there is
  # no tighter source restriction available for that specific need.
  security_rule {
    name                       = "AllowSSHFromAdmin"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ssh_source_cidr
    destination_address_prefix = "*"
  }

  # Ports 9000 (SonarQube) and 5432 (Postgres) are deliberately absent
  # here — they are never bound to the VM's public interface in the
  # first place (see docker-compose.yml.tftpl), so there is nothing
  # to allow or deny for them at the NSG either. Defence in depth:
  # even a docker-compose mistake that published them would still hit
  # this NSG's implicit deny-all-else.

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "tools" {
  subnet_id                 = azurerm_subnet.tools.id
  network_security_group_id = azurerm_network_security_group.sonarqube.id
}

resource "azurerm_public_ip" "sonarqube" {
  name                = "pip-sonarqube-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

locals {
  # nip.io resolves "<ip>.nip.io" to <ip> with zero DNS setup — a real
  # public hostname (so Let's Encrypt will issue for it), not a hack
  # that skips TLS. Set var.dns_label to a real domain later; nothing
  # else here changes.
  fqdn = coalesce(var.dns_label, "${azurerm_public_ip.sonarqube.ip_address}.nip.io")
}

resource "azurerm_network_interface" "sonarqube" {
  name                = "nic-sonarqube-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.tools.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.sonarqube.id
  }

  tags = var.tags
}

# ============================================================
# DATA DISK — everything that must survive VM/container recreation
# lives here, not on the OS disk and not in an unnamed Docker volume.
# ============================================================

resource "azurerm_managed_disk" "data" {
  name                 = "disk-sonarqube-data-${var.environment}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb

  tags = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.sonarqube.id
  lun                = "0"
  caching            = "ReadWrite"
}

# ============================================================
# BACKUP STORAGE — dedicated account, private container, lifecycle
# policy does the retention. The VM writes here via Managed Identity;
# nothing else has, or needs, a key/connection-string for it.
# ============================================================

resource "azurerm_storage_account" "backup" {
  name                = "stsonarbkp${var.environment}${substr(md5("${var.resource_group_name}-01"), 0, 6)}" # "-01": old name still held by the expired subscription
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = var.tags
}

resource "azurerm_storage_container" "backups" {
  name                  = "sonarqube-backups"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "backup_retention" {
  storage_account_id = azurerm_storage_account.backup.id

  rule {
    name    = "expire-old-backups"
    enabled = true

    filters {
      prefix_match = [azurerm_storage_container.backups.name]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.backup_retention_days
      }
    }
  }
}

resource "azurerm_role_assignment" "vm_backup_write" {
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.sonarqube.identity[0].principal_id
}

# ============================================================
# THE VM
#
# custom_data (cloud-init) does the ENTIRE application bootstrap —
# format+mount the data disk, generate the Postgres password locally
# (never through a Terraform variable, so it never enters state),
# write docker-compose.yml + Caddyfile, install azcopy, start
# everything, schedule the nightly backup timer. Nothing is manual
# except what's documented in SONARQUBE.md as a genuine manual step
# (first login, creating projects/tokens — those are SonarQube
# application state, not infrastructure).
# ============================================================

resource "azurerm_linux_virtual_machine" "sonarqube" {
  name                = "vm-sonarqube-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size

  network_interface_ids = [azurerm_network_interface.sonarqube.id]

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Matches the AKS node pool's OS (Ubuntu 24.04 LTS) — one distro to
  # reason about across the whole fleet, not a coincidence.
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    fqdn                 = local.fqdn
    storage_account_name = azurerm_storage_account.backup.name
    backup_container     = azurerm_storage_container.backups.name
  }))

  tags = var.tags
}
