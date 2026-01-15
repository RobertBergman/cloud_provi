# =============================================================================
# Local Network Gateways (On-Premises Definitions)
# =============================================================================
# Represents the on-prem routers from GCP simulation.
# Each router gets its own LNG for redundancy.
# =============================================================================

# -----------------------------------------------------------------------------
# Local Network Gateway - Router 1
# -----------------------------------------------------------------------------

resource "azurerm_local_network_gateway" "router_1" {
  name                = "lng-onprem-router-1-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  gateway_address     = var.router_1_public_ip

  # Address spaces that this LNG represents
  # Note: IPv6 support may depend on preview feature registration
  address_space = var.onprem_ipv4_ranges

  # BGP configuration
  bgp_settings {
    asn                 = var.onprem_bgp_asn
    bgp_peering_address = "169.254.21.5" # On-prem BGP peer for router 1
  }

  tags = {
    Environment = var.environment
    Router      = "router-1"
  }
}

# -----------------------------------------------------------------------------
# Local Network Gateway - Router 2
# -----------------------------------------------------------------------------

resource "azurerm_local_network_gateway" "router_2" {
  name                = "lng-onprem-router-2-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  gateway_address     = var.router_2_public_ip

  # Address spaces that this LNG represents
  address_space = var.onprem_ipv4_ranges

  # BGP configuration
  bgp_settings {
    asn                 = var.onprem_bgp_asn
    bgp_peering_address = "169.254.21.6" # On-prem BGP peer for router 2
  }

  tags = {
    Environment = var.environment
    Router      = "router-2"
  }
}
