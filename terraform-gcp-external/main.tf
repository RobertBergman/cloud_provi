# =============================================================================
# GCP Cloud Infrastructure with External VPN to On-Prem Simulation
# =============================================================================
# This configuration creates:
# - Dual-stack VPC with workload subnet
# - Firewall rules for VPN and internal traffic
# - HA VPN Gateway connecting to external on-prem routers
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  name_suffix = "${var.environment}-${var.region}"

  # Cloud VPC ranges
  cloud_ipv4_cidr = "10.10.0.0/16"
  cloud_ipv6_cidr = "fd20:f:1::/48"

  # On-prem ranges (must match terraform-onprem-sim)
  onprem_ipv4_cidr     = "192.168.0.0/16"
  onprem_ipv6_internal = "fd20:e:1::/48"
  onprem_ipv6_bgp      = "dead:beef::/48" # Advertised via BGP

  # BGP ASNs
  cloud_asn  = 65515
  onprem_asn = 65001

  # IPv4 BGP Link-Local Addresses (169.254.x.x/30)
  bgp_v4_cloud_0  = "169.254.0.1"
  bgp_v4_onprem_0 = "169.254.0.2"
  bgp_v4_cloud_1  = "169.254.1.1"
  bgp_v4_onprem_1 = "169.254.1.2"

  # IPv6 BGP Peering Addresses (fdff:1::/64 ULA range, /126 per link)
  bgp_v6_cloud_0  = "fdff:1::1"
  bgp_v6_onprem_0 = "fdff:1::2"
  bgp_v6_cloud_1  = "fdff:1::5"
  bgp_v6_onprem_1 = "fdff:1::6"
}

# =============================================================================
# Cloud VPC Network
# =============================================================================

resource "google_compute_network" "cloud" {
  name                            = "vpc-gcp-cloud-${var.environment}"
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  enable_ula_internal_ipv6        = true
  internal_ipv6_range             = local.cloud_ipv6_cidr
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "cloud_workload" {
  name                     = "subnet-cloud-workload-${local.name_suffix}"
  ip_cidr_range            = cidrsubnet(local.cloud_ipv4_cidr, 8, 1) # 10.10.1.0/24
  region                   = var.region
  network                  = google_compute_network.cloud.id
  private_ip_google_access = true
  stack_type               = "IPV4_IPV6"
  ipv6_access_type         = "INTERNAL"
}

# =============================================================================
# Firewall Rules
# =============================================================================

# Allow SSH from anywhere (for management)
resource "google_compute_firewall" "allow_ssh" {
  name    = "fw-allow-ssh-${local.name_suffix}"
  network = google_compute_network.cloud.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-ssh"]
}

# Allow internal IPv4 traffic
resource "google_compute_firewall" "allow_internal_ipv4" {
  name    = "fw-allow-internal-ipv4-${local.name_suffix}"
  network = google_compute_network.cloud.name

  allow {
    protocol = "all"
  }

  source_ranges = [
    local.cloud_ipv4_cidr,
    local.onprem_ipv4_cidr,
  ]
}

# Allow internal IPv6 traffic (separate rule due to GCP limitation)
resource "google_compute_firewall" "allow_internal_ipv6" {
  name    = "fw-allow-internal-ipv6-${local.name_suffix}"
  network = google_compute_network.cloud.name

  allow {
    protocol = "all"
  }

  source_ranges = [
    local.cloud_ipv6_cidr,
    local.onprem_ipv6_internal,
    local.onprem_ipv6_bgp,
  ]
}

# Allow ICMP for ping tests
resource "google_compute_firewall" "allow_icmp" {
  name    = "fw-allow-icmp-${local.name_suffix}"
  network = google_compute_network.cloud.name

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
}

# Allow ICMPv6 for ping6 tests
resource "google_compute_firewall" "allow_icmpv6" {
  name    = "fw-allow-icmpv6-${local.name_suffix}"
  network = google_compute_network.cloud.name

  allow {
    protocol = "58" # ICMPv6
  }

  source_ranges = ["::/0"]
}
