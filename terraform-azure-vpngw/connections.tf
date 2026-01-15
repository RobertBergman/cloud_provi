# =============================================================================
# VPN Gateway Connections
# =============================================================================
# IPsec connections to on-prem routers with custom IPsec/IKE policy.
# Uses IKEv2 which is required for IPv6 support.
# =============================================================================

# -----------------------------------------------------------------------------
# Connection to Router 1
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network_gateway_connection" "to_router_1" {
  name                       = "conn-to-onprem-router-1-${local.name_suffix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.main.id
  local_network_gateway_id   = azurerm_local_network_gateway.router_1.id

  shared_key = var.vpn_shared_key

  # Enable BGP for dynamic routing
  enable_bgp = true

  # IKEv2 is required for IPv6 support
  connection_protocol = "IKEv2"

  # Custom IPsec/IKE policy
  ipsec_policy {
    # IKE Phase 1
    ike_encryption = "AES256"
    ike_integrity  = "SHA256"
    dh_group       = "DHGroup14"

    # IPsec Phase 2
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"

    # SA lifetimes
    sa_lifetime  = 27000      # seconds (7.5 hours)
    sa_datasize  = 102400000  # KB (~100GB)
  }

  tags = {
    Environment = var.environment
    Destination = "router-1"
  }
}

# -----------------------------------------------------------------------------
# Connection to Router 2
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network_gateway_connection" "to_router_2" {
  name                       = "conn-to-onprem-router-2-${local.name_suffix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.main.id
  local_network_gateway_id   = azurerm_local_network_gateway.router_2.id

  shared_key = var.vpn_shared_key

  # Enable BGP for dynamic routing
  enable_bgp = true

  # IKEv2 is required for IPv6 support
  connection_protocol = "IKEv2"

  # Custom IPsec/IKE policy (same as router 1)
  ipsec_policy {
    # IKE Phase 1
    ike_encryption = "AES256"
    ike_integrity  = "SHA256"
    dh_group       = "DHGroup14"

    # IPsec Phase 2
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS14"

    # SA lifetimes
    sa_lifetime  = 27000
    sa_datasize  = 102400000
  }

  tags = {
    Environment = var.environment
    Destination = "router-2"
  }
}
