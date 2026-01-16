# =============================================================================
# Test VM for Connectivity Validation
# =============================================================================

resource "google_compute_instance" "test_vm" {
  name         = "vm-cloud-test-${local.name_suffix}"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  tags = ["allow-ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.cloud.id
    subnetwork = google_compute_subnetwork.cloud_workload.id
    stack_type = "IPV4_IPV6"

    access_config {
      # Ephemeral public IP for SSH access
    }
    # Note: No ipv6_access_config since subnet uses INTERNAL IPv6
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y iputils-ping traceroute mtr tcpdump

    echo "Test VM ready for connectivity testing"
    echo "IPv4: $(hostname -I | awk '{print $1}')"
    echo "IPv6: $(ip -6 addr show dev ens4 scope global | grep inet6 | awk '{print $2}')"
  EOF

  scheduling {
    preemptible                 = true
    automatic_restart           = false
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
  }

  service_account {
    scopes = ["cloud-platform"]
  }
}
