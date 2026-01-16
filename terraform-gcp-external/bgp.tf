# =============================================================================
# Cloud Router and BGP Configuration
# =============================================================================
# This configuration creates:
# - Cloud Router with custom BGP advertisements
# - IPv4 BGP interfaces and peers
# - IPv6 BGP interfaces and peers (DEDICATED sessions, not MP-BGP)
#
# CRITICAL: GCP requires dedicated IPv6 BGP sessions for proper IPv6 route
# installation. Using enable_ipv6=true on IPv4 peers (MP-BGP) does NOT work.
# =============================================================================

# =============================================================================
# Cloud Router
# =============================================================================

resource "google_compute_router" "cloud" {
  name    = "router-cloud-${local.name_suffix}"
  region  = var.region
  network = google_compute_network.cloud.id

  bgp {
    asn               = local.cloud_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]

    # Explicitly advertise both IPv4 and IPv6 ranges
    advertised_ip_ranges {
      range       = local.cloud_ipv4_cidr
      description = "Cloud IPv4 range"
    }
    advertised_ip_ranges {
      range       = local.cloud_ipv6_cidr
      description = "Cloud IPv6 range"
    }
  }
}

# =============================================================================
# IPv4 BGP Interfaces and Peers
# =============================================================================

# Interface for Tunnel 0 (to Router 1) - IPv4
resource "google_compute_router_interface" "cloud_v4_0" {
  name       = "interface-v4-0"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = "${local.bgp_v4_cloud_0}/30"
  vpn_tunnel = google_compute_vpn_tunnel.to_onprem_0.name
}

# Interface for Tunnel 1 (to Router 2) - IPv4
resource "google_compute_router_interface" "cloud_v4_1" {
  name       = "interface-v4-1"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = "${local.bgp_v4_cloud_1}/30"
  vpn_tunnel = google_compute_vpn_tunnel.to_onprem_1.name
}

# BGP Peer for Tunnel 0 - IPv4
resource "google_compute_router_peer" "cloud_v4_0" {
  name                      = "peer-v4-to-onprem-0"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = local.bgp_v4_onprem_0
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_v4_0.name
}

# BGP Peer for Tunnel 1 - IPv4
resource "google_compute_router_peer" "cloud_v4_1" {
  name                      = "peer-v4-to-onprem-1"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = local.bgp_v4_onprem_1
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_v4_1.name
}

# =============================================================================
# IPv6 BGP Interfaces and Peers (DEDICATED SESSIONS)
# =============================================================================
# These are CRITICAL for proper IPv6 route installation in GCP.
# MP-BGP (using enable_ipv6=true on IPv4 peers) does NOT install IPv6 routes.
# =============================================================================

# Interface for Tunnel 0 (to Router 1) - IPv6
resource "google_compute_router_interface" "cloud_v6_0" {
  name       = "interface-v6-0"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = "${local.bgp_v6_cloud_0}/126"
  vpn_tunnel = google_compute_vpn_tunnel.to_onprem_0.name
}

# Interface for Tunnel 1 (to Router 2) - IPv6
resource "google_compute_router_interface" "cloud_v6_1" {
  name       = "interface-v6-1"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = "${local.bgp_v6_cloud_1}/126"
  vpn_tunnel = google_compute_vpn_tunnel.to_onprem_1.name
}

# BGP Peer for Tunnel 0 - IPv6
resource "google_compute_router_peer" "cloud_v6_0" {
  name                      = "peer-v6-to-onprem-0"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = local.bgp_v6_onprem_0
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_v6_0.name
  enable_ipv6               = true
}

# BGP Peer for Tunnel 1 - IPv6
resource "google_compute_router_peer" "cloud_v6_1" {
  name                      = "peer-v6-to-onprem-1"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = local.bgp_v6_onprem_1
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_v6_1.name
  enable_ipv6               = true
}
