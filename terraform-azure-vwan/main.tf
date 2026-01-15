# Azure Dual-Stack Virtual WAN Infrastructure
# Terraform configuration for repeatable deployments

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
  }

  # Uncomment to use remote state
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstate"
  #   container_name       = "tfstate"
  #   key                  = "dualstack-vwan.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

# =============================================================================
# Variables
# =============================================================================

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "prod"
}

variable "location" {
  type        = string
  description = "Azure region for resources"
  default     = "eastus2"
}

variable "vnet_ipv4_cidr" {
  type        = string
  description = "IPv4 CIDR for the virtual network"
  default     = "10.1.0.0/16"
}

variable "vnet_ipv6_cidr" {
  type        = string
  description = "IPv6 CIDR for the virtual network"
  default     = "2001:db8:1::/48"
}

variable "hub_ipv4_cidr" {
  type        = string
  description = "IPv4 CIDR for the virtual hub"
  default     = "10.0.0.0/24"
}

variable "hub_ipv6_cidr" {
  type        = string
  description = "IPv6 CIDR for the virtual hub"
  default     = "fd00:db8::/64"
}

variable "onprem_public_ip" {
  type        = string
  description = "Public IP of on-premises VPN device (ignored if onprem_sim_enabled=true)"
  default     = ""
}

variable "onprem_bgp_asn" {
  type        = number
  description = "BGP ASN for on-premises"
  default     = 65001
}

variable "onprem_bgp_peer_ip" {
  type        = string
  description = "BGP peer IP for on-premises (ignored if onprem_sim_enabled=true)"
  default     = ""
}

variable "onprem_ipv4_ranges" {
  type        = list(string)
  description = "On-premises IPv4 address ranges"
  default     = ["192.168.0.0/16"]
}

variable "onprem_ipv6_ranges" {
  type        = list(string)
  description = "On-premises IPv6 address ranges"
  default     = ["2001:db8:2::/48"]
}

variable "vpn_shared_key" {
  type        = string
  description = "Pre-shared key for VPN connection"
  sensitive   = true
}

variable "vpn_scale_units" {
  type        = number
  description = "VPN Gateway scale units (1 = 500 Mbps)"
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

locals {
  name_prefix = "dualstack-${var.environment}-${var.location}"

  default_tags = {
    Environment = var.environment
    Project     = "dual-stack-vwan"
    ManagedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }

  tags = merge(local.default_tags, var.tags)

  subnets = {
    workload-01 = {
      ipv4 = cidrsubnet(var.vnet_ipv4_cidr, 8, 1)
      ipv6 = "2001:db8:1:1::/64"
    }
    workload-02 = {
      ipv4 = cidrsubnet(var.vnet_ipv4_cidr, 8, 2)
      ipv6 = "2001:db8:1:2::/64"
    }
    mgmt = {
      ipv4 = cidrsubnet(var.vnet_ipv4_cidr, 8, 3)
      ipv6 = "2001:db8:1:3::/64"
    }
  }

  # Use simulated on-prem values if enabled, otherwise use provided values
  effective_onprem_public_ip   = var.onprem_sim_enabled ? azurerm_public_ip.onprem_vpn[0].ip_address : var.onprem_public_ip
  effective_onprem_bgp_asn     = var.onprem_sim_enabled ? local.onprem_bgp_asn : var.onprem_bgp_asn
  effective_onprem_bgp_peer_ip = var.onprem_sim_enabled ? local.onprem_bgp_peer_ip : var.onprem_bgp_peer_ip
  effective_onprem_ipv4_ranges = var.onprem_sim_enabled ? [var.onprem_sim_vnet_ipv4] : var.onprem_ipv4_ranges
  effective_onprem_ipv6_ranges = var.onprem_sim_enabled ? [var.onprem_sim_vnet_ipv6] : var.onprem_ipv6_ranges
}

# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

# =============================================================================
# Virtual WAN
# =============================================================================

resource "azurerm_virtual_wan" "main" {
  name                           = "vwan-${local.name_prefix}"
  resource_group_name            = azurerm_resource_group.main.name
  location                       = azurerm_resource_group.main.location
  type                           = "Standard"
  allow_branch_to_branch_traffic = true

  tags = local.tags
}

# =============================================================================
# Virtual Hub (Dual-Stack)
# =============================================================================

resource "azurerm_virtual_hub" "main" {
  name                = "vhub-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_wan_id      = azurerm_virtual_wan.main.id
  address_prefix      = var.hub_ipv4_cidr
  sku                 = "Standard"

  tags = local.tags
}

# =============================================================================
# VPN Gateway in Virtual Hub
# =============================================================================

resource "azurerm_vpn_gateway" "main" {
  name                = "vpngw-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_hub_id      = azurerm_virtual_hub.main.id
  scale_unit          = var.vpn_scale_units

  bgp_settings {
    asn         = 65515
    peer_weight = 0
  }

  tags = local.tags
}

# =============================================================================
# Virtual Network (Dual-Stack)
# =============================================================================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-workload-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_ipv4_cidr, var.vnet_ipv6_cidr]

  tags = local.tags
}

# =============================================================================
# Subnets (Dual-Stack)
# =============================================================================

resource "azurerm_subnet" "subnets" {
  for_each = local.subnets

  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value.ipv4, each.value.ipv6]
}

# =============================================================================
# VNet to Hub Connection
# =============================================================================

resource "azurerm_virtual_hub_connection" "vnet" {
  name                      = "conn-vnet-workload"
  virtual_hub_id            = azurerm_virtual_hub.main.id
  remote_virtual_network_id = azurerm_virtual_network.main.id
  internet_security_enabled = true
}

# =============================================================================
# VPN Site (On-Premises)
# =============================================================================

resource "azurerm_vpn_site" "onprem" {
  name                = "vpnsite-onprem-hq"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_wan_id      = azurerm_virtual_wan.main.id
  # Note: Azure VPN Sites do not support IPv6 address prefixes yet
  address_cidrs       = local.effective_onprem_ipv4_ranges

  link {
    name          = "link-primary"
    ip_address    = local.effective_onprem_public_ip
    speed_in_mbps = 100

    bgp {
      asn             = local.effective_onprem_bgp_asn
      peering_address = local.effective_onprem_bgp_peer_ip
    }
  }

  tags = local.tags

  # When using simulated on-prem, wait for the public IP to be allocated
  depends_on = [azurerm_public_ip.onprem_vpn]
}

# =============================================================================
# VPN Connection
# =============================================================================

resource "azurerm_vpn_gateway_connection" "onprem" {
  name               = "conn-onprem-hq"
  vpn_gateway_id     = azurerm_vpn_gateway.main.id
  remote_vpn_site_id = azurerm_vpn_site.onprem.id

  vpn_link {
    name             = "link-primary"
    vpn_site_link_id = azurerm_vpn_site.onprem.link[0].id
    shared_key       = var.vpn_shared_key
    bgp_enabled      = true

    ipsec_policy {
      dh_group                 = "DHGroup14"
      ike_encryption_algorithm = "AES256"
      ike_integrity_algorithm  = "SHA256"
      encryption_algorithm     = "GCMAES256"
      integrity_algorithm      = "GCMAES256"
      pfs_group                = "PFS14"
      sa_data_size_kb          = 102400000
      sa_lifetime_sec          = 27000
    }
  }
}

# =============================================================================
# Network Security Groups
# =============================================================================

resource "azurerm_network_security_group" "workload" {
  name                = "nsg-workload-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Note: Azure NSG rules cannot mix IPv4 and IPv6 in the same rule
  security_rule {
    name                       = "AllowOnPremInboundIPv4"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = local.effective_onprem_ipv4_ranges
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowOnPremInboundIPv6"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = local.effective_onprem_ipv6_ranges
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowICMP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  for_each = { for k, v in azurerm_subnet.subnets : k => v if k != "mgmt" }

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

# =============================================================================
# Outputs
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "virtual_wan_id" {
  description = "ID of the Virtual WAN"
  value       = azurerm_virtual_wan.main.id
}

output "virtual_hub_id" {
  description = "ID of the Virtual Hub"
  value       = azurerm_virtual_hub.main.id
}

output "vpn_gateway_id" {
  description = "ID of the VPN Gateway"
  value       = azurerm_vpn_gateway.main.id
}

output "vpn_gateway_bgp_settings" {
  description = "BGP settings for the VPN Gateway"
  value = {
    asn                  = azurerm_vpn_gateway.main.bgp_settings[0].asn
    bgp_peering_address  = azurerm_vpn_gateway.main.bgp_settings[0].instance_0_bgp_peering_address
  }
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "subnet_ids" {
  description = "IDs of all subnets"
  value       = { for k, v in azurerm_subnet.subnets : k => v.id }
}
