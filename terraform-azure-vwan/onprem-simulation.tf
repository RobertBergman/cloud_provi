# =============================================================================
# Simulated On-Premises Environment
# =============================================================================
# This creates a separate VNet with a strongSwan VPN gateway VM to simulate
# an on-premises datacenter for testing the Azure Virtual WAN S2S VPN.
#
# Note: Azure S2S VPN requires IPsec/IKEv2, not OpenVPN (SSL-based).
# strongSwan provides IPsec capabilities needed for the tunnel.
# =============================================================================

# -----------------------------------------------------------------------------
# Variables for On-Prem Simulation
# -----------------------------------------------------------------------------

variable "onprem_sim_enabled" {
  type        = bool
  description = "Enable the simulated on-premises environment"
  default     = true
}

variable "onprem_sim_location" {
  type        = string
  description = "Azure region for simulated on-prem (use different region for realism)"
  default     = "westus2"
}

variable "onprem_sim_vnet_ipv4" {
  type        = string
  description = "IPv4 CIDR for simulated on-prem VNet"
  default     = "192.168.0.0/16"
}

variable "onprem_sim_vnet_ipv6" {
  type        = string
  description = "IPv6 CIDR for simulated on-prem VNet"
  default     = "2001:db8:2::/48"
}

variable "onprem_sim_vm_size" {
  type        = string
  description = "VM size for the VPN gateway"
  default     = "Standard_B2s"
}

variable "onprem_sim_admin_username" {
  type        = string
  description = "Admin username for the VPN VM"
  default     = "azureuser"
}

variable "onprem_sim_admin_ssh_key" {
  type        = string
  description = "SSH public key for the VPN VM admin"
  default     = ""
}

variable "onprem_sim_admin_password" {
  type        = string
  description = "Admin password (used if SSH key not provided)"
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  onprem_name_prefix = "onprem-sim-${var.environment}"

  onprem_subnets = {
    gateway = {
      ipv4 = cidrsubnet(var.onprem_sim_vnet_ipv4, 8, 0)  # 192.168.0.0/24
      ipv6 = "2001:db8:2:0::/64"
    }
    workload = {
      ipv4 = cidrsubnet(var.onprem_sim_vnet_ipv4, 8, 1)  # 192.168.1.0/24
      ipv6 = "2001:db8:2:1::/64"
    }
  }

  # BGP settings for simulated on-prem
  onprem_bgp_asn     = 65001
  onprem_bgp_peer_ip = cidrhost(local.onprem_subnets.gateway.ipv4, 4)  # 192.168.0.4
}

# -----------------------------------------------------------------------------
# Resource Group for Simulated On-Prem
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "onprem" {
  count = var.onprem_sim_enabled ? 1 : 0

  name     = "rg-${local.onprem_name_prefix}-${var.onprem_sim_location}"
  location = var.onprem_sim_location

  tags = merge(local.tags, {
    Purpose = "Simulated On-Premises Environment"
  })
}

# -----------------------------------------------------------------------------
# Virtual Network (Simulated On-Prem - Dual Stack)
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "onprem" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                = "vnet-${local.onprem_name_prefix}"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location
  address_space       = [var.onprem_sim_vnet_ipv4, var.onprem_sim_vnet_ipv6]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

resource "azurerm_subnet" "onprem_gateway" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                 = "snet-gateway"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = [local.onprem_subnets.gateway.ipv4, local.onprem_subnets.gateway.ipv6]
}

resource "azurerm_subnet" "onprem_workload" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  virtual_network_name = azurerm_virtual_network.onprem[0].name
  address_prefixes     = [local.onprem_subnets.workload.ipv4, local.onprem_subnets.workload.ipv6]
}

# -----------------------------------------------------------------------------
# Public IP for VPN Gateway VM
# -----------------------------------------------------------------------------

resource "azurerm_public_ip" "onprem_vpn" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                = "pip-vpn-${local.onprem_name_prefix}"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Network Security Group for VPN Gateway
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "onprem_vpn" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                = "nsg-vpn-${local.onprem_name_prefix}"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location

  # IKE (UDP 500)
  security_rule {
    name                       = "AllowIKE"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "500"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # IPsec NAT-T (UDP 4500)
  security_rule {
    name                       = "AllowIPsecNATT"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "4500"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # ESP Protocol (IP Protocol 50)
  security_rule {
    name                       = "AllowESP"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Allow ESP (Protocol 50) - NSG doesn't support protocol numbers directly"
  }

  # SSH for management
  security_rule {
    name                       = "AllowSSH"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # Restrict to your IP in production
    destination_address_prefix = "*"
  }

  # ICMP for testing
  security_rule {
    name                       = "AllowICMP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Network Interface for VPN Gateway VM
# -----------------------------------------------------------------------------

resource "azurerm_network_interface" "onprem_vpn" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                 = "nic-vpn-${local.onprem_name_prefix}"
  resource_group_name  = azurerm_resource_group.onprem[0].name
  location             = azurerm_resource_group.onprem[0].location
  enable_ip_forwarding = true  # Required for routing

  ip_configuration {
    name                          = "ipconfig-v4"
    subnet_id                     = azurerm_subnet.onprem_gateway[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.onprem_bgp_peer_ip
    public_ip_address_id          = azurerm_public_ip.onprem_vpn[0].id
    primary                       = true
  }

  ip_configuration {
    name                          = "ipconfig-v6"
    subnet_id                     = azurerm_subnet.onprem_gateway[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(local.onprem_subnets.gateway.ipv6, 4)
    private_ip_address_version    = "IPv6"
  }

  tags = local.tags
}

resource "azurerm_network_interface_security_group_association" "onprem_vpn" {
  count = var.onprem_sim_enabled ? 1 : 0

  network_interface_id      = azurerm_network_interface.onprem_vpn[0].id
  network_security_group_id = azurerm_network_security_group.onprem_vpn[0].id
}

# -----------------------------------------------------------------------------
# VPN Gateway VM (strongSwan)
# -----------------------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "onprem_vpn" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                  = "vm-vpn-${local.onprem_name_prefix}"
  resource_group_name   = azurerm_resource_group.onprem[0].name
  location              = azurerm_resource_group.onprem[0].location
  size                  = var.onprem_sim_vm_size
  admin_username        = var.onprem_sim_admin_username
  network_interface_ids = [azurerm_network_interface.onprem_vpn[0].id]

  # Use SSH key if provided, otherwise use password
  disable_password_authentication = var.onprem_sim_admin_ssh_key != "" ? true : false
  admin_password                  = var.onprem_sim_admin_ssh_key != "" ? null : var.onprem_sim_admin_password

  dynamic "admin_ssh_key" {
    for_each = var.onprem_sim_admin_ssh_key != "" ? [1] : []
    content {
      username   = var.onprem_sim_admin_username
      public_key = var.onprem_sim_admin_ssh_key
    }
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-vpn-${local.onprem_name_prefix}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-vpn.yaml", {
    onprem_private_ip      = local.onprem_bgp_peer_ip
    onprem_public_ip       = azurerm_public_ip.onprem_vpn[0].ip_address
    onprem_bgp_asn         = local.onprem_bgp_asn
    onprem_ipv4_cidr       = var.onprem_sim_vnet_ipv4
    onprem_ipv6_cidr       = var.onprem_sim_vnet_ipv6
    azure_vnet_ipv4_cidr   = var.vnet_ipv4_cidr
    azure_vnet_ipv6_cidr   = var.vnet_ipv6_cidr
    azure_hub_ipv4_cidr    = var.hub_ipv4_cidr
    vpn_psk                = var.vpn_shared_key
    # These will be filled in after Azure VPN Gateway is created
    azure_vpn_gateway_ip_0 = "PLACEHOLDER_AZURE_VPN_IP_0"
    azure_vpn_gateway_ip_1 = "PLACEHOLDER_AZURE_VPN_IP_1"
    azure_bgp_asn          = 65515
    azure_bgp_ip_0         = "PLACEHOLDER_AZURE_BGP_IP_0"
    azure_bgp_ip_1         = "PLACEHOLDER_AZURE_BGP_IP_1"
  }))

  tags = local.tags

  depends_on = [azurerm_public_ip.onprem_vpn]
}

# -----------------------------------------------------------------------------
# Route Table for On-Prem Workload Subnet
# -----------------------------------------------------------------------------

resource "azurerm_route_table" "onprem_workload" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                = "rt-workload-${local.onprem_name_prefix}"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location

  # Route Azure VNet traffic through the VPN gateway VM
  route {
    name                   = "ToAzureVNet"
    address_prefix         = var.vnet_ipv4_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.onprem_bgp_peer_ip
  }

  route {
    name                   = "ToAzureHub"
    address_prefix         = var.hub_ipv4_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.onprem_bgp_peer_ip
  }

  tags = local.tags
}

resource "azurerm_subnet_route_table_association" "onprem_workload" {
  count = var.onprem_sim_enabled ? 1 : 0

  subnet_id      = azurerm_subnet.onprem_workload[0].id
  route_table_id = azurerm_route_table.onprem_workload[0].id
}

# -----------------------------------------------------------------------------
# Test VM in On-Prem Workload Subnet
# -----------------------------------------------------------------------------

resource "azurerm_network_interface" "onprem_test" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                = "nic-test-${local.onprem_name_prefix}"
  resource_group_name = azurerm_resource_group.onprem[0].name
  location            = azurerm_resource_group.onprem[0].location

  ip_configuration {
    name                          = "ipconfig-v4"
    subnet_id                     = azurerm_subnet.onprem_workload[0].id
    private_ip_address_allocation = "Dynamic"
    primary                       = true
  }

  ip_configuration {
    name                          = "ipconfig-v6"
    subnet_id                     = azurerm_subnet.onprem_workload[0].id
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version    = "IPv6"
  }

  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "onprem_test" {
  count = var.onprem_sim_enabled ? 1 : 0

  name                            = "vm-test-${local.onprem_name_prefix}"
  resource_group_name             = azurerm_resource_group.onprem[0].name
  location                        = azurerm_resource_group.onprem[0].location
  size                            = "Standard_B1s"
  admin_username                  = var.onprem_sim_admin_username
  disable_password_authentication = var.onprem_sim_admin_ssh_key != "" ? true : false
  admin_password                  = var.onprem_sim_admin_ssh_key != "" ? null : var.onprem_sim_admin_password
  network_interface_ids           = [azurerm_network_interface.onprem_test[0].id]

  dynamic "admin_ssh_key" {
    for_each = var.onprem_sim_admin_ssh_key != "" ? [1] : []
    content {
      username   = var.onprem_sim_admin_username
      public_key = var.onprem_sim_admin_ssh_key
    }
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-test-${local.onprem_name_prefix}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Outputs for Simulated On-Prem
# -----------------------------------------------------------------------------

output "onprem_resource_group_name" {
  description = "Name of the simulated on-prem resource group"
  value       = var.onprem_sim_enabled ? azurerm_resource_group.onprem[0].name : null
}

output "onprem_vpn_public_ip" {
  description = "Public IP of the simulated on-prem VPN gateway"
  value       = var.onprem_sim_enabled ? azurerm_public_ip.onprem_vpn[0].ip_address : null
}

output "onprem_vpn_private_ip" {
  description = "Private IP of the simulated on-prem VPN gateway"
  value       = var.onprem_sim_enabled ? local.onprem_bgp_peer_ip : null
}

output "onprem_bgp_asn" {
  description = "BGP ASN for simulated on-prem"
  value       = var.onprem_sim_enabled ? local.onprem_bgp_asn : null
}

output "onprem_vpn_vm_id" {
  description = "ID of the VPN gateway VM"
  value       = var.onprem_sim_enabled ? azurerm_linux_virtual_machine.onprem_vpn[0].id : null
}

output "onprem_test_vm_private_ip" {
  description = "Private IP of the test VM in simulated on-prem"
  value       = var.onprem_sim_enabled ? azurerm_network_interface.onprem_test[0].private_ip_address : null
}

output "onprem_connection_info" {
  description = "Information needed to configure the VPN connection"
  value = var.onprem_sim_enabled ? {
    vpn_public_ip  = azurerm_public_ip.onprem_vpn[0].ip_address
    bgp_asn        = local.onprem_bgp_asn
    bgp_peer_ip    = local.onprem_bgp_peer_ip
    address_spaces = [var.onprem_sim_vnet_ipv4, var.onprem_sim_vnet_ipv6]
  } : null
}
