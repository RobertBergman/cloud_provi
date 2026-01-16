# =============================================================================
# Outputs
# =============================================================================

output "gcp_vpn_gateway_ips" {
  description = "GCP HA VPN Gateway public IPs"
  value = {
    interface_0 = google_compute_ha_vpn_gateway.cloud.vpn_interfaces[0].ip_address
    interface_1 = google_compute_ha_vpn_gateway.cloud.vpn_interfaces[1].ip_address
  }
}

output "cloud_router_asn" {
  description = "GCP Cloud Router BGP ASN"
  value       = local.cloud_asn
}

output "test_vm_ips" {
  description = "Test VM IP addresses"
  value = {
    name      = google_compute_instance.test_vm.name
    ipv4      = google_compute_instance.test_vm.network_interface[0].network_ip
    ipv6      = google_compute_instance.test_vm.network_interface[0].ipv6_address
    public_ip = google_compute_instance.test_vm.network_interface[0].access_config[0].nat_ip
  }
}

# =============================================================================
# VPN Configuration for On-Prem Routers
# =============================================================================

output "onprem_router_1_config" {
  description = "VPN configuration for on-prem router 1"
  sensitive   = true
  value = {
    tunnel_name        = "gcp-tunnel-r1"
    remote_ip          = google_compute_ha_vpn_gateway.cloud.vpn_interfaces[0].ip_address
    psk                = var.vpn_shared_secret
    local_inside_ip    = local.bgp_v4_onprem_0
    remote_inside_ip   = local.bgp_v4_cloud_0
    local_inside_ipv6  = local.bgp_v6_onprem_0
    remote_inside_ipv6 = local.bgp_v6_cloud_0
    remote_asn         = local.cloud_asn
  }
}

output "onprem_router_2_config" {
  description = "VPN configuration for on-prem router 2"
  sensitive   = true
  value = {
    tunnel_name        = "gcp-tunnel-r2"
    remote_ip          = google_compute_ha_vpn_gateway.cloud.vpn_interfaces[1].ip_address
    psk                = var.vpn_shared_secret
    local_inside_ip    = local.bgp_v4_onprem_1
    remote_inside_ip   = local.bgp_v4_cloud_1
    local_inside_ipv6  = local.bgp_v6_onprem_1
    remote_inside_ipv6 = local.bgp_v6_cloud_1
    remote_asn         = local.cloud_asn
  }
}

# JSON configs for use with configure-gcp-vpn.sh script
output "onprem_router_1_json_config" {
  description = "JSON config for Router 1 (use with configure-gcp-vpn.sh)"
  sensitive   = true
  value = jsonencode({
    tunnels = [{
      name               = "gcp-tunnel-r1"
      remote_ip          = google_compute_ha_vpn_gateway.cloud.vpn_interfaces[0].ip_address
      psk                = var.vpn_shared_secret
      local_inside_ip    = local.bgp_v4_onprem_0
      remote_inside_ip   = local.bgp_v4_cloud_0
      local_inside_ipv6  = local.bgp_v6_onprem_0
      remote_inside_ipv6 = local.bgp_v6_cloud_0
      remote_asn         = local.cloud_asn
    }]
  })
}

output "onprem_router_2_json_config" {
  description = "JSON config for Router 2 (use with configure-gcp-vpn.sh)"
  sensitive   = true
  value = jsonencode({
    tunnels = [{
      name               = "gcp-tunnel-r2"
      remote_ip          = google_compute_ha_vpn_gateway.cloud.vpn_interfaces[1].ip_address
      psk                = var.vpn_shared_secret
      local_inside_ip    = local.bgp_v4_onprem_1
      remote_inside_ip   = local.bgp_v4_cloud_1
      local_inside_ipv6  = local.bgp_v6_onprem_1
      remote_inside_ipv6 = local.bgp_v6_cloud_1
      remote_asn         = local.cloud_asn
    }]
  })
}

# =============================================================================
# Quick Reference Commands
# =============================================================================

output "ssh_commands" {
  description = "SSH commands for accessing VMs"
  value = {
    test_vm = "gcloud compute ssh ${google_compute_instance.test_vm.name} --zone=${google_compute_instance.test_vm.zone} --project=${var.project_id}"
  }
}

output "verification_commands" {
  description = "Commands to verify VPN and BGP status"
  value = {
    router_status = "gcloud compute routers get-status ${google_compute_router.cloud.name} --region=${var.region} --project=${var.project_id}"
    tunnel_status = "gcloud compute vpn-tunnels list --region=${var.region} --project=${var.project_id}"
    routes        = "gcloud compute routes list --filter='network:${google_compute_network.cloud.name}' --project=${var.project_id}"
  }
}
