# =============================================================================
# Azure VPN Gateway - Main Infrastructure
# =============================================================================
# This deployment tests Azure VPN Gateway (non-VWAN) dual-stack capabilities.
# Key difference from VWAN: VPN Gateway has preview IPv6 support for inner traffic.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
  }
}

provider "azurerm" {
  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  name_suffix = "${var.environment}-${var.location}"

  # Subnet calculations
  gateway_subnet_ipv4 = cidrsubnet(var.vnet_ipv4_cidr, 11, 0) # /27 from /16
  workload_subnet_ipv4 = cidrsubnet(var.vnet_ipv4_cidr, 8, 1)  # /24 from /16
  workload_subnet_ipv6 = "fd20:d:1:1::/64"

  # Azure BGP configuration
  azure_bgp_asn = 65515

  # BGP peering IPs (APIPA range for Azure VPN Gateway)
  azure_bgp_ip_1 = "169.254.21.1"
  azure_bgp_ip_2 = "169.254.21.2"
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = "rg-azure-vpngw-${local.name_suffix}"
  location = var.location

  tags = {
    Environment = var.environment
    Purpose     = "Azure VPN Gateway dual-stack test"
  }
}

# -----------------------------------------------------------------------------
# Virtual Network (Dual-Stack)
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "main" {
  name                = "vnet-azure-vpngw-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_ipv4_cidr, var.vnet_ipv6_cidr]

  tags = {
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

# GatewaySubnet - MUST be IPv4 only (Azure requirement)
# Name must be exactly "GatewaySubnet"
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.gateway_subnet_ipv4]
}

# Workload subnet - Dual-stack for test VMs
resource "azurerm_subnet" "workload" {
  name                 = "snet-workload-${local.name_suffix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [local.workload_subnet_ipv4, local.workload_subnet_ipv6]
}

# -----------------------------------------------------------------------------
# Network Security Group
# -----------------------------------------------------------------------------

resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # SSH access
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # ICMP from on-prem (IPv4)
  security_rule {
    name                       = "AllowICMPv4FromOnPrem"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.onprem_ipv4_ranges
    destination_address_prefix = "*"
  }

  # ICMP from on-prem (IPv6)
  security_rule {
    name                       = "AllowICMPv6FromOnPrem"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.onprem_ipv6_ranges
    destination_address_prefix = "*"
  }

  # All traffic from on-prem (IPv4)
  security_rule {
    name                       = "AllowAllFromOnPremIPv4"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.onprem_ipv4_ranges
    destination_address_prefix = "*"
  }

  # All traffic from on-prem (IPv6)
  security_rule {
    name                       = "AllowAllFromOnPremIPv6"
    priority                   = 301
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.onprem_ipv6_ranges
    destination_address_prefix = "*"
  }

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}
