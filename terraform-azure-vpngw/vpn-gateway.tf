# =============================================================================
# Azure VPN Gateway Configuration
# =============================================================================
# Active-Active VPN Gateway with BGP for dual-stack connectivity testing.
# Requires VpnGw1 or higher SKU for IPv6 preview support.
# =============================================================================

# -----------------------------------------------------------------------------
# Public IPs for VPN Gateway
# -----------------------------------------------------------------------------

resource "azurerm_public_ip" "vpngw_pip_1" {
  name                = "pip-vpngw-1-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
    Purpose     = "VPN Gateway Instance 0"
  }
}

resource "azurerm_public_ip" "vpngw_pip_2" {
  count               = var.enable_active_active ? 1 : 0
  name                = "pip-vpngw-2-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
    Purpose     = "VPN Gateway Instance 1"
  }
}

# -----------------------------------------------------------------------------
# VPN Gateway
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network_gateway" "main" {
  name                = "vpngw-azure-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  type     = "Vpn"
  vpn_type = "RouteBased"

  # Must be VpnGw1 or higher for IPv6 preview support
  sku           = var.vpn_gateway_sku
  generation    = "Generation1"
  active_active = var.enable_active_active
  enable_bgp    = true

  # BGP configuration
  bgp_settings {
    asn = local.azure_bgp_asn

    # APIPA addresses for BGP peering
    peering_addresses {
      ip_configuration_name = "vnetGatewayConfig1"
      apipa_addresses       = [local.azure_bgp_ip_1]
    }

    dynamic "peering_addresses" {
      for_each = var.enable_active_active ? [1] : []
      content {
        ip_configuration_name = "vnetGatewayConfig2"
        apipa_addresses       = [local.azure_bgp_ip_2]
      }
    }
  }

  # Primary IP configuration
  ip_configuration {
    name                          = "vnetGatewayConfig1"
    public_ip_address_id          = azurerm_public_ip.vpngw_pip_1.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  # Secondary IP configuration (Active-Active)
  dynamic "ip_configuration" {
    for_each = var.enable_active_active ? [1] : []
    content {
      name                          = "vnetGatewayConfig2"
      public_ip_address_id          = azurerm_public_ip.vpngw_pip_2[0].id
      private_ip_address_allocation = "Dynamic"
      subnet_id                     = azurerm_subnet.gateway.id
    }
  }

  tags = {
    Environment = var.environment
    Purpose     = "Dual-stack VPN test"
  }
}
