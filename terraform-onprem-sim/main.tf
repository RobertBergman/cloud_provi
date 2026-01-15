# =============================================================================
# GCP On-Prem Simulation - Dual VPN Routers with FreeSwan + FRR
# =============================================================================
# This simulates an on-premises environment with redundant VPN routers
# for testing cloud VPN connectivity (AWS, GCP, Azure)
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

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Network ranges
  vpc_ipv4_cidr      = "192.168.0.0/16"
  vpc_ipv6_cidr      = "fd20:e:1::/48"
  router_subnet_ipv4 = "192.168.0.0/24"
  workload_subnet_ipv4 = "192.168.1.0/24"

  # Router IPs
  router_1_ip = "192.168.0.10"
  router_2_ip = "192.168.0.11"
  test_vm_ip  = "192.168.1.100"

  # BGP
  onprem_asn = 65001

  # Naming
  name_suffix = "${var.environment}"
}

# =============================================================================
# VPC Network
# =============================================================================

resource "google_compute_network" "onprem" {
  name                            = "vpc-onprem-sim-${local.name_suffix}"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
  enable_ula_internal_ipv6        = true
  internal_ipv6_range             = local.vpc_ipv6_cidr
}

# =============================================================================
# Subnets
# =============================================================================

# Router subnet - where the VPN routers live
resource "google_compute_subnetwork" "router" {
  name                     = "subnet-router-${local.name_suffix}"
  ip_cidr_range            = local.router_subnet_ipv4
  region                   = var.region
  network                  = google_compute_network.onprem.id
  private_ip_google_access = true
  stack_type               = "IPV4_IPV6"
  ipv6_access_type         = "INTERNAL"
}

# Workload subnet - where the test VM lives (behind routers)
resource "google_compute_subnetwork" "workload" {
  name                     = "subnet-workload-${local.name_suffix}"
  ip_cidr_range            = local.workload_subnet_ipv4
  region                   = var.region
  network                  = google_compute_network.onprem.id
  private_ip_google_access = true
  stack_type               = "IPV4_IPV6"
  ipv6_access_type         = "INTERNAL"
}

# =============================================================================
# Firewall Rules
# =============================================================================

# Allow IKE and IPsec from internet (for VPN)
resource "google_compute_firewall" "allow_vpn" {
  name    = "fw-onprem-allow-vpn-${local.name_suffix}"
  network = google_compute_network.onprem.id

  allow {
    protocol = "udp"
    ports    = ["500", "4500"]  # IKE and NAT-T
  }

  allow {
    protocol = "esp"  # IPsec ESP
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["vpn-router"]
}

# Allow SSH from internet (for management)
resource "google_compute_firewall" "allow_ssh" {
  name    = "fw-onprem-allow-ssh-${local.name_suffix}"
  network = google_compute_network.onprem.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-allowed"]
}

# Allow internal IPv4 traffic
resource "google_compute_firewall" "allow_internal_ipv4" {
  name    = "fw-onprem-allow-internal-ipv4-${local.name_suffix}"
  network = google_compute_network.onprem.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [local.vpc_ipv4_cidr, "10.0.0.0/8"]  # Include cloud ranges
}

# Allow internal IPv6 traffic
resource "google_compute_firewall" "allow_internal_ipv6" {
  name    = "fw-onprem-allow-internal-ipv6-${local.name_suffix}"
  network = google_compute_network.onprem.id

  allow {
    protocol = "58"  # ICMPv6
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  # On-prem IPv6 + potential cloud IPv6 ranges
  source_ranges = [local.vpc_ipv6_cidr]
}

# =============================================================================
# Static Public IPs for Routers
# =============================================================================

resource "google_compute_address" "router_1" {
  name         = "ip-router-1-${local.name_suffix}"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_address" "router_2" {
  name         = "ip-router-2-${local.name_suffix}"
  region       = var.region
  address_type = "EXTERNAL"
}

# =============================================================================
# Router VMs (FreeSwan + FRR)
# =============================================================================

resource "google_compute_instance" "router_1" {
  name         = "vm-router-1-${local.name_suffix}"
  machine_type = var.router_machine_type
  zone         = "${var.region}-a"

  tags = ["vpn-router", "ssh-allowed"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.router.id
    network_ip = local.router_1_ip

    access_config {
      nat_ip = google_compute_address.router_1.address
    }

    stack_type = "IPV4_IPV6"
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init-router.yaml", {
      router_id      = "1"
      router_ip      = local.router_1_ip
      peer_router_ip = local.router_2_ip
      bgp_asn        = local.onprem_asn
      ipv4_networks  = local.vpc_ipv4_cidr
      ipv6_networks  = local.vpc_ipv6_cidr
    })
  }

  can_ip_forward = true  # Required for routing

  service_account {
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
}

resource "google_compute_instance" "router_2" {
  name         = "vm-router-2-${local.name_suffix}"
  machine_type = var.router_machine_type
  zone         = "${var.region}-b"

  tags = ["vpn-router", "ssh-allowed"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.router.id
    network_ip = local.router_2_ip

    access_config {
      nat_ip = google_compute_address.router_2.address
    }

    stack_type = "IPV4_IPV6"
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init-router.yaml", {
      router_id      = "2"
      router_ip      = local.router_2_ip
      peer_router_ip = local.router_1_ip
      bgp_asn        = local.onprem_asn
      ipv4_networks  = local.vpc_ipv4_cidr
      ipv6_networks  = local.vpc_ipv6_cidr
    })
  }

  can_ip_forward = true  # Required for routing

  service_account {
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
}

# =============================================================================
# Test VM (behind routers)
# =============================================================================

resource "google_compute_instance" "test_vm" {
  name         = "vm-onprem-test-${local.name_suffix}"
  machine_type = var.test_vm_machine_type
  zone         = "${var.region}-a"

  tags = ["ssh-allowed"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.workload.id
    network_ip = local.test_vm_ip

    # No external IP - traffic goes through routers
    stack_type = "IPV4_IPV6"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    # Install basic tools
    apt-get update
    apt-get install -y traceroute mtr-tiny tcpdump

    # Add routes to cloud networks via routers (ECMP)
    # These will be added after router config is complete
    echo "Test VM ready for connectivity testing"
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true
}

# =============================================================================
# Routes - Cloud traffic goes through routers
# =============================================================================

# Route to AWS/cloud IPv4 via router 1 (primary)
resource "google_compute_route" "to_cloud_ipv4_r1" {
  name              = "route-to-cloud-ipv4-r1-${local.name_suffix}"
  network           = google_compute_network.onprem.id
  dest_range        = "10.0.0.0/8"
  next_hop_instance = google_compute_instance.router_1.id
  next_hop_instance_zone = "${var.region}-a"
  priority          = 100
  tags              = []  # Applies to all instances
}

# Route to AWS/cloud IPv4 via router 2 (backup)
resource "google_compute_route" "to_cloud_ipv4_r2" {
  name              = "route-to-cloud-ipv4-r2-${local.name_suffix}"
  network           = google_compute_network.onprem.id
  dest_range        = "10.0.0.0/8"
  next_hop_instance = google_compute_instance.router_2.id
  next_hop_instance_zone = "${var.region}-b"
  priority          = 200  # Higher number = lower priority (backup)
  tags              = []
}
