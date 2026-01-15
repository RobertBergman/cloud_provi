# =============================================================================
# Outputs for GCP On-Prem Simulation
# =============================================================================
# These outputs are used to configure cloud VPN connections (AWS, GCP, Azure)
# =============================================================================

output "router_1_public_ip" {
  description = "Public IP of router 1 (for cloud Customer Gateway / VPN Site)"
  value       = google_compute_address.router_1.address
}

output "router_2_public_ip" {
  description = "Public IP of router 2 (for cloud Customer Gateway / VPN Site)"
  value       = google_compute_address.router_2.address
}

output "onprem_bgp_asn" {
  description = "BGP ASN for on-prem routers"
  value       = local.onprem_asn
}

output "onprem_ipv4_cidrs" {
  description = "On-prem IPv4 CIDR ranges to advertise"
  value       = [local.vpc_ipv4_cidr]
}

output "onprem_ipv6_cidrs" {
  description = "On-prem IPv6 CIDR ranges to advertise"
  value       = [local.vpc_ipv6_cidr]
}

output "router_1_private_ip" {
  description = "Private IP of router 1"
  value       = local.router_1_ip
}

output "router_2_private_ip" {
  description = "Private IP of router 2"
  value       = local.router_2_ip
}

output "test_vm_private_ip" {
  description = "Private IP of test VM (target for connectivity tests)"
  value       = local.test_vm_ip
}

output "router_ssh_commands" {
  description = "SSH commands to access router VMs"
  value       = <<-EOT
    # Router 1
    gcloud compute ssh ${google_compute_instance.router_1.name} --zone=${var.region}-a --project=${var.project_id}
    # Or directly:
    ssh ubuntu@${google_compute_address.router_1.address}

    # Router 2
    gcloud compute ssh ${google_compute_instance.router_2.name} --zone=${var.region}-b --project=${var.project_id}
    # Or directly:
    ssh ubuntu@${google_compute_address.router_2.address}
  EOT
}

output "test_vm_ssh_command" {
  description = "SSH command to access test VM (via IAP since no public IP)"
  value       = "gcloud compute ssh ${google_compute_instance.test_vm.name} --zone=${var.region}-a --project=${var.project_id} --tunnel-through-iap"
}

output "vpn_configuration_summary" {
  description = "Summary of on-prem VPN configuration for cloud setup"
  value       = <<-EOT
    ============================================================
    ON-PREM SIMULATION - VPN CONFIGURATION SUMMARY
    ============================================================

    Use these values when configuring cloud VPN (AWS/GCP/Azure):

    ROUTER 1:
      Public IP: ${google_compute_address.router_1.address}
      Private IP: ${local.router_1_ip}

    ROUTER 2:
      Public IP: ${google_compute_address.router_2.address}
      Private IP: ${local.router_2_ip}

    BGP:
      ASN: ${local.onprem_asn}

    ADVERTISED PREFIXES:
      IPv4: ${local.vpc_ipv4_cidr}
      IPv6: ${local.vpc_ipv6_cidr}

    TEST TARGET:
      IPv4: ${local.test_vm_ip}
      IPv6: (assigned by GCP from ${local.vpc_ipv6_cidr})

    ============================================================
  EOT
}
