# ============================================================
# HomeEase Virtual Network
# ============================================================

resource "azurerm_virtual_network" "this" {
  name                = "vnet-homeease-${var.environment}"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# ============================================================
# AKS Subnet
# ============================================================

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.aks_subnet_prefix
}

# ============================================================
# Private Endpoint Subnet
# ============================================================

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.private_endpoint_subnet_prefix
}

# ============================================================
# AKS Node Subnet NSG
# ============================================================

resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # ----------------------------------------------------------
  # Allow Azure Load Balancer health probes
  # ----------------------------------------------------------
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # ----------------------------------------------------------
  # Allow HTTP traffic to NodePorts
  # Azure Load Balancer forwards public :80 to ingress NodePort
  # ----------------------------------------------------------
  security_rule {
    name                       = "AllowHTTPNodePort"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # ----------------------------------------------------------
  # Allow HTTPS traffic to NodePorts
  # ----------------------------------------------------------
  security_rule {
    name                       = "AllowHTTPSNodePort"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # ----------------------------------------------------------
  # Optional direct HTTP access
  # ----------------------------------------------------------
  security_rule {
    name                       = "AllowHTTPInbound"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # ----------------------------------------------------------
  # Optional direct HTTPS access
  # ----------------------------------------------------------
  security_rule {
    name                       = "AllowHTTPSInbound"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# ============================================================
# Attach NSG to AKS subnet
# ============================================================

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# ============================================================
# Private Endpoint NSG
# ============================================================

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pe-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# ============================================================
# Attach Private Endpoint NSG
# ============================================================

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}