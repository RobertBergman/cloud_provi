# =============================================================================
# VPN Gateway and Tunnels
# =============================================================================
# This configuration creates:
# - HA VPN Gateway (GCP cloud side)
# - External VPN Gateway (represents on-prem routers)
# - VPN Tunnels connecting GCP to on-prem
# =============================================================================

# =============================================================================
# HA VPN Gateway (GCP Cloud Side)
# =============================================================================

resource "google_compute_ha_vpn_gateway" "cloud" {
  name       = "vpngw-cloud-${local.name_suffix}"
  region     = var.region
  network    = google_compute_network.cloud.id
  stack_type = "IPV4_IPV6"
}

# =============================================================================
# External VPN Gateway (Represents On-Prem Routers)
# =============================================================================

resource "google_compute_external_vpn_gateway" "onprem" {
  name            = "ext-vpngw-onprem-${var.environment}"
  redundancy_type = "TWO_IPS_REDUNDANCY" # 2 on-prem routers
  description     = "On-prem VPN routers (LibreSwan)"

  interface {
    id         = 0
    ip_address = var.onprem_router_1_ip
  }

  interface {
    id         = 1
    ip_address = var.onprem_router_2_ip
  }
}

# =============================================================================
# VPN Tunnels (GCP to On-Prem)
# =============================================================================

# Tunnel 0: GCP Interface 0 -> On-Prem Router 1
resource "google_compute_vpn_tunnel" "to_onprem_0" {
  name                            = "tunnel-to-onprem-0-${local.name_suffix}"
  region                          = var.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.cloud.id
  vpn_gateway_interface           = 0
  peer_external_gateway           = google_compute_external_vpn_gateway.onprem.id
  peer_external_gateway_interface = 0
  shared_secret                   = var.vpn_shared_secret
  router                          = google_compute_router.cloud.id
  ike_version                     = 2
}

# Tunnel 1: GCP Interface 1 -> On-Prem Router 2
resource "google_compute_vpn_tunnel" "to_onprem_1" {
  name                            = "tunnel-to-onprem-1-${local.name_suffix}"
  region                          = var.region
  vpn_gateway                     = google_compute_ha_vpn_gateway.cloud.id
  vpn_gateway_interface           = 1
  peer_external_gateway           = google_compute_external_vpn_gateway.onprem.id
  peer_external_gateway_interface = 1
  shared_secret                   = var.vpn_shared_secret
  router                          = google_compute_router.cloud.id
  ike_version                     = 2
}
