# GCP Dual-Stack VPN Infrastructure
# Site-to-Site VPN with BGP to simulated on-premises

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  description = "GCP region for cloud resources"
  default     = "us-central1"
}

variable "onprem_region" {
  type        = string
  description = "GCP region for simulated on-prem"
  default     = "us-east1"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "prod"
}

variable "vpn_shared_secret" {
  type        = string
  description = "Shared secret for VPN tunnels"
  sensitive   = true
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Cloud VPC ranges (dual-stack)
  cloud_ipv4_cidr = "10.1.0.0/16"
  cloud_ipv6_cidr = "fd20:a:1::/48"  # ULA range within fd20::/20 required by GCP

  # On-prem VPC ranges (dual-stack)
  onprem_ipv4_cidr = "192.168.0.0/16"
  onprem_ipv6_cidr = "fd20:b:1::/48"  # ULA range within fd20::/20 required by GCP

  # BGP ASNs
  cloud_asn  = 65001
  onprem_asn = 65002

  # BGP IPv6 Link-Local Peering Addresses (Reserved ULA fdff:1::/64)
  # Using /126 for point-to-point links (4 addresses per link)
  # Tunnel 0 Pair: fdff:1::0/126 (::0, ::1, ::2, ::3)
  bgp_v6_cloud_0  = "fdff:1::1/126"
  bgp_v6_onprem_0 = "fdff:1::2/126"

  # Tunnel 1 Pair: fdff:1::4/126 (::4, ::5, ::6, ::7)
  bgp_v6_cloud_1  = "fdff:1::5/126"
  bgp_v6_onprem_1 = "fdff:1::6/126"

  labels = {
    environment = var.environment
    project     = "dual-stack-vpn"
    managed_by  = "terraform"
  }
}

# =============================================================================
# Cloud VPC Network (Dual-Stack)
# =============================================================================

resource "google_compute_network" "cloud" {
  name                            = "vpc-cloud-${var.environment}"
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  enable_ula_internal_ipv6        = true  # Enable IPv6
  internal_ipv6_range             = local.cloud_ipv6_cidr
}

resource "google_compute_subnetwork" "cloud_workload" {
  name                     = "subnet-workload-${var.environment}"
  ip_cidr_range            = cidrsubnet(local.cloud_ipv4_cidr, 8, 1)  # 10.1.1.0/24
  region                   = var.region
  network                  = google_compute_network.cloud.id
  private_ip_google_access = true

  # Enable dual-stack
  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL"
}

# =============================================================================
# Cloud Router (for BGP)
# =============================================================================

resource "google_compute_router" "cloud" {
  name    = "router-cloud-${var.environment}"
  region  = var.region
  network = google_compute_network.cloud.id

  bgp {
    asn               = local.cloud_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]

    # Advertise both IPv4 and IPv6 ranges
    advertised_ip_ranges {
      range = local.cloud_ipv4_cidr
    }
    advertised_ip_ranges {
      range = local.cloud_ipv6_cidr
    }
  }
}

# =============================================================================
# HA VPN Gateway (Cloud Side)
# =============================================================================

resource "google_compute_ha_vpn_gateway" "cloud" {
  name    = "vpngw-cloud-${var.environment}"
  region  = var.region
  network = google_compute_network.cloud.id

  # HA VPN supports dual-stack
  stack_type = "IPV4_IPV6"
}

# =============================================================================
# Simulated On-Prem VPC Network
# =============================================================================

resource "google_compute_network" "onprem" {
  name                            = "vpc-onprem-${var.environment}"
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"
  enable_ula_internal_ipv6        = true
  internal_ipv6_range             = local.onprem_ipv6_cidr
}

resource "google_compute_subnetwork" "onprem_workload" {
  name                     = "subnet-onprem-workload-${var.environment}"
  ip_cidr_range            = cidrsubnet(local.onprem_ipv4_cidr, 8, 1)  # 192.168.1.0/24
  region                   = var.onprem_region
  network                  = google_compute_network.onprem.id
  private_ip_google_access = true

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL"
}

# =============================================================================
# On-Prem Router (for BGP)
# =============================================================================

resource "google_compute_router" "onprem" {
  name    = "router-onprem-${var.environment}"
  region  = var.onprem_region
  network = google_compute_network.onprem.id

  bgp {
    asn               = local.onprem_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]

    advertised_ip_ranges {
      range = local.onprem_ipv4_cidr
    }
    advertised_ip_ranges {
      range = local.onprem_ipv6_cidr
    }
  }
}

# =============================================================================
# HA VPN Gateway (On-Prem Side)
# =============================================================================

resource "google_compute_ha_vpn_gateway" "onprem" {
  name    = "vpngw-onprem-${var.environment}"
  region  = var.onprem_region
  network = google_compute_network.onprem.id

  stack_type = "IPV4_IPV6"
}

# =============================================================================
# VPN Tunnels (Cloud to On-Prem) - 2 tunnels for HA
# =============================================================================

resource "google_compute_vpn_tunnel" "cloud_to_onprem_0" {
  name                  = "tunnel-cloud-to-onprem-0"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.cloud.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem.id
  shared_secret         = var.vpn_shared_secret
  router                = google_compute_router.cloud.id
  vpn_gateway_interface = 0

  depends_on = [
    google_compute_ha_vpn_gateway.cloud,
    google_compute_ha_vpn_gateway.onprem
  ]
}

resource "google_compute_vpn_tunnel" "cloud_to_onprem_1" {
  name                  = "tunnel-cloud-to-onprem-1"
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.cloud.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem.id
  shared_secret         = var.vpn_shared_secret
  router                = google_compute_router.cloud.id
  vpn_gateway_interface = 1

  depends_on = [
    google_compute_ha_vpn_gateway.cloud,
    google_compute_ha_vpn_gateway.onprem
  ]
}

# =============================================================================
# VPN Tunnels (On-Prem to Cloud) - 2 tunnels for HA
# =============================================================================

resource "google_compute_vpn_tunnel" "onprem_to_cloud_0" {
  name                  = "tunnel-onprem-to-cloud-0"
  region                = var.onprem_region
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.cloud.id
  shared_secret         = var.vpn_shared_secret
  router                = google_compute_router.onprem.id
  vpn_gateway_interface = 0

  depends_on = [
    google_compute_ha_vpn_gateway.cloud,
    google_compute_ha_vpn_gateway.onprem
  ]
}

resource "google_compute_vpn_tunnel" "onprem_to_cloud_1" {
  name                  = "tunnel-onprem-to-cloud-1"
  region                = var.onprem_region
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.cloud.id
  shared_secret         = var.vpn_shared_secret
  router                = google_compute_router.onprem.id
  vpn_gateway_interface = 1

  depends_on = [
    google_compute_ha_vpn_gateway.cloud,
    google_compute_ha_vpn_gateway.onprem
  ]
}

# =============================================================================
# BGP Peer Interfaces and Sessions (Cloud Router)
# =============================================================================

resource "google_compute_router_interface" "cloud_interface_0" {
  name       = "interface-cloud-0"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = "169.254.0.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.cloud_to_onprem_0.name
}

resource "google_compute_router_interface" "cloud_interface_1" {
  name       = "interface-cloud-1"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = "169.254.1.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.cloud_to_onprem_1.name
}

resource "google_compute_router_peer" "cloud_peer_0" {
  name                      = "peer-cloud-to-onprem-0"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = "169.254.0.2"
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_interface_0.name
}

resource "google_compute_router_peer" "cloud_peer_1" {
  name                      = "peer-cloud-to-onprem-1"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = "169.254.1.2"
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_interface_1.name
}

# =============================================================================
# BGP Peer Interfaces and Sessions (On-Prem Router)
# =============================================================================

resource "google_compute_router_interface" "onprem_interface_0" {
  name       = "interface-onprem-0"
  router     = google_compute_router.onprem.name
  region     = var.onprem_region
  ip_range   = "169.254.0.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_to_cloud_0.name
}

resource "google_compute_router_interface" "onprem_interface_1" {
  name       = "interface-onprem-1"
  router     = google_compute_router.onprem.name
  region     = var.onprem_region
  ip_range   = "169.254.1.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_to_cloud_1.name
}

resource "google_compute_router_peer" "onprem_peer_0" {
  name                      = "peer-onprem-to-cloud-0"
  router                    = google_compute_router.onprem.name
  region                    = var.onprem_region
  peer_ip_address           = "169.254.0.1"
  peer_asn                  = local.cloud_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.onprem_interface_0.name
}

resource "google_compute_router_peer" "onprem_peer_1" {
  name                      = "peer-onprem-to-cloud-1"
  router                    = google_compute_router.onprem.name
  region                    = var.onprem_region
  peer_ip_address           = "169.254.1.1"
  peer_asn                  = local.cloud_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.onprem_interface_1.name
}

# =============================================================================
# IPv6 BGP Interfaces and Sessions (Dedicated IPv6 BGP for proper route installation)
# =============================================================================

# --- Cloud Side IPv6 Interfaces ---
resource "google_compute_router_interface" "cloud_interface_0_v6" {
  name       = "interface-cloud-0-v6"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = local.bgp_v6_cloud_0
  vpn_tunnel = google_compute_vpn_tunnel.cloud_to_onprem_0.name
}

resource "google_compute_router_interface" "cloud_interface_1_v6" {
  name       = "interface-cloud-1-v6"
  router     = google_compute_router.cloud.name
  region     = var.region
  ip_range   = local.bgp_v6_cloud_1
  vpn_tunnel = google_compute_vpn_tunnel.cloud_to_onprem_1.name
}

# --- On-Prem Side IPv6 Interfaces ---
resource "google_compute_router_interface" "onprem_interface_0_v6" {
  name       = "interface-onprem-0-v6"
  router     = google_compute_router.onprem.name
  region     = var.onprem_region
  ip_range   = local.bgp_v6_onprem_0
  vpn_tunnel = google_compute_vpn_tunnel.onprem_to_cloud_0.name
}

resource "google_compute_router_interface" "onprem_interface_1_v6" {
  name       = "interface-onprem-1-v6"
  router     = google_compute_router.onprem.name
  region     = var.onprem_region
  ip_range   = local.bgp_v6_onprem_1
  vpn_tunnel = google_compute_vpn_tunnel.onprem_to_cloud_1.name
}

# --- Cloud Side IPv6 Peers ---
resource "google_compute_router_peer" "cloud_peer_0_v6" {
  name                      = "peer-cloud-to-onprem-0-v6"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = split("/", local.bgp_v6_onprem_0)[0]
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_interface_0_v6.name
  enable_ipv6               = true
}

resource "google_compute_router_peer" "cloud_peer_1_v6" {
  name                      = "peer-cloud-to-onprem-1-v6"
  router                    = google_compute_router.cloud.name
  region                    = var.region
  peer_ip_address           = split("/", local.bgp_v6_onprem_1)[0]
  peer_asn                  = local.onprem_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.cloud_interface_1_v6.name
  enable_ipv6               = true
}

# --- On-Prem Side IPv6 Peers ---
resource "google_compute_router_peer" "onprem_peer_0_v6" {
  name                      = "peer-onprem-to-cloud-0-v6"
  router                    = google_compute_router.onprem.name
  region                    = var.onprem_region
  peer_ip_address           = split("/", local.bgp_v6_cloud_0)[0]
  peer_asn                  = local.cloud_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.onprem_interface_0_v6.name
  enable_ipv6               = true
}

resource "google_compute_router_peer" "onprem_peer_1_v6" {
  name                      = "peer-onprem-to-cloud-1-v6"
  router                    = google_compute_router.onprem.name
  region                    = var.onprem_region
  peer_ip_address           = split("/", local.bgp_v6_cloud_1)[0]
  peer_asn                  = local.cloud_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.onprem_interface_1_v6.name
  enable_ipv6               = true
}

# =============================================================================
# Firewall Rules (Cloud VPC)
# =============================================================================

resource "google_compute_firewall" "cloud_allow_internal" {
  name    = "fw-cloud-allow-internal"
  network = google_compute_network.cloud.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  source_ranges = [local.cloud_ipv4_cidr, local.onprem_ipv4_cidr]
}

resource "google_compute_firewall" "cloud_allow_internal_ipv6" {
  name    = "fw-cloud-allow-internal-ipv6"
  network = google_compute_network.cloud.id

  allow {
    protocol = "58"  # ICMPv6
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  source_ranges = [local.cloud_ipv6_cidr, local.onprem_ipv6_cidr]
}

resource "google_compute_firewall" "cloud_allow_ssh" {
  name    = "fw-cloud-allow-ssh"
  network = google_compute_network.cloud.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh"]
}

# =============================================================================
# Firewall Rules (On-Prem VPC)
# =============================================================================

resource "google_compute_firewall" "onprem_allow_internal" {
  name    = "fw-onprem-allow-internal"
  network = google_compute_network.onprem.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  source_ranges = [local.cloud_ipv4_cidr, local.onprem_ipv4_cidr]
}

resource "google_compute_firewall" "onprem_allow_internal_ipv6" {
  name    = "fw-onprem-allow-internal-ipv6"
  network = google_compute_network.onprem.id

  allow {
    protocol = "58"  # ICMPv6
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  source_ranges = [local.cloud_ipv6_cidr, local.onprem_ipv6_cidr]
}

resource "google_compute_firewall" "onprem_allow_ssh" {
  name    = "fw-onprem-allow-ssh"
  network = google_compute_network.onprem.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh"]
}

# =============================================================================
# Test VMs
# =============================================================================

resource "google_compute_instance" "cloud_test" {
  name         = "vm-cloud-test-${var.environment}"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  tags = ["ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.cloud_workload.id

    # Enable both IPv4 and IPv6
    stack_type = "IPV4_IPV6"

    access_config {
      # Ephemeral public IP for SSH access
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  labels = local.labels
}

resource "google_compute_instance" "onprem_test" {
  name         = "vm-onprem-test-${var.environment}"
  machine_type = "e2-micro"
  zone         = "${var.onprem_region}-b"

  tags = ["ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.onprem_workload.id

    stack_type = "IPV4_IPV6"

    access_config {
      # Ephemeral public IP for SSH access
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  labels = local.labels
}

# =============================================================================
# Outputs
# =============================================================================

output "cloud_vpc_id" {
  description = "Cloud VPC ID"
  value       = google_compute_network.cloud.id
}

output "onprem_vpc_id" {
  description = "On-prem VPC ID"
  value       = google_compute_network.onprem.id
}

output "cloud_vpn_gateway" {
  description = "Cloud VPN Gateway details"
  value = {
    name       = google_compute_ha_vpn_gateway.cloud.name
    ip_address = google_compute_ha_vpn_gateway.cloud.vpn_interfaces
  }
}

output "onprem_vpn_gateway" {
  description = "On-prem VPN Gateway details"
  value = {
    name       = google_compute_ha_vpn_gateway.onprem.name
    ip_address = google_compute_ha_vpn_gateway.onprem.vpn_interfaces
  }
}

output "cloud_test_vm" {
  description = "Cloud test VM details"
  value = {
    name        = google_compute_instance.cloud_test.name
    internal_ip = google_compute_instance.cloud_test.network_interface[0].network_ip
    external_ip = google_compute_instance.cloud_test.network_interface[0].access_config[0].nat_ip
  }
}

output "onprem_test_vm" {
  description = "On-prem test VM details"
  value = {
    name        = google_compute_instance.onprem_test.name
    internal_ip = google_compute_instance.onprem_test.network_interface[0].network_ip
    external_ip = google_compute_instance.onprem_test.network_interface[0].access_config[0].nat_ip
  }
}

output "vpn_tunnel_status" {
  description = "VPN tunnel names (check status with gcloud)"
  value = [
    google_compute_vpn_tunnel.cloud_to_onprem_0.name,
    google_compute_vpn_tunnel.cloud_to_onprem_1.name,
    google_compute_vpn_tunnel.onprem_to_cloud_0.name,
    google_compute_vpn_tunnel.onprem_to_cloud_1.name
  ]
}

output "bgp_session_info" {
  description = "BGP session configuration"
  value = {
    cloud_asn  = local.cloud_asn
    onprem_asn = local.onprem_asn
  }
}

output "test_commands" {
  description = "Commands to test connectivity"
  value       = <<-EOT
    # SSH to cloud VM
    gcloud compute ssh ${google_compute_instance.cloud_test.name} --zone=${var.region}-a

    # SSH to on-prem VM
    gcloud compute ssh ${google_compute_instance.onprem_test.name} --zone=${var.onprem_region}-b

    # From cloud VM, ping on-prem VM (IPv4)
    ping ${google_compute_instance.onprem_test.network_interface[0].network_ip}

    # Check VPN tunnel status
    gcloud compute vpn-tunnels describe tunnel-cloud-to-onprem-0 --region=${var.region}

    # Check BGP session status
    gcloud compute routers get-status router-cloud-${var.environment} --region=${var.region}
  EOT
}
