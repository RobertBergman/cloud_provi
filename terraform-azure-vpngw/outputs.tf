# =============================================================================
# Outputs
# =============================================================================
# Provides configuration details needed for on-prem router setup.
# =============================================================================

# -----------------------------------------------------------------------------
# VPN Gateway Details
# -----------------------------------------------------------------------------

output "vpn_gateway_public_ip_1" {
  description = "Public IP of VPN Gateway instance 0"
  value       = azurerm_public_ip.vpngw_pip_1.ip_address
}

output "vpn_gateway_public_ip_2" {
  description = "Public IP of VPN Gateway instance 1 (Active-Active)"
  value       = var.enable_active_active ? azurerm_public_ip.vpngw_pip_2[0].ip_address : null
}

output "vpn_gateway_bgp_asn" {
  description = "BGP ASN of Azure VPN Gateway"
  value       = local.azure_bgp_asn
}

output "vpn_gateway_bgp_ip_1" {
  description = "BGP peering IP for VPN Gateway instance 0"
  value       = local.azure_bgp_ip_1
}

output "vpn_gateway_bgp_ip_2" {
  description = "BGP peering IP for VPN Gateway instance 1"
  value       = local.azure_bgp_ip_2
}

# -----------------------------------------------------------------------------
# Test VM Details
# -----------------------------------------------------------------------------

output "test_vm_public_ip" {
  description = "Public IP of test VM for SSH access"
  value       = azurerm_public_ip.test_vm.ip_address
}

output "test_vm_private_ip_v4" {
  description = "Private IPv4 of test VM"
  value       = azurerm_network_interface.test_vm.private_ip_address
}

output "test_vm_ssh_command" {
  description = "SSH command to connect to test VM"
  value       = "ssh ${var.test_vm_admin_username}@${azurerm_public_ip.test_vm.ip_address}"
}

# -----------------------------------------------------------------------------
# Network Details
# -----------------------------------------------------------------------------

output "azure_vnet_ipv4" {
  description = "Azure VNet IPv4 CIDR"
  value       = var.vnet_ipv4_cidr
}

output "azure_vnet_ipv6" {
  description = "Azure VNet IPv6 CIDR"
  value       = var.vnet_ipv6_cidr
}

output "azure_workload_subnet_ipv4" {
  description = "Workload subnet IPv4 CIDR"
  value       = local.workload_subnet_ipv4
}

output "azure_workload_subnet_ipv6" {
  description = "Workload subnet IPv6 CIDR"
  value       = local.workload_subnet_ipv6
}

# -----------------------------------------------------------------------------
# Router Configuration Summary
# -----------------------------------------------------------------------------

output "router_1_config" {
  description = "Configuration for on-prem router 1 to connect to Azure"
  value = {
    tunnel_name          = "azure-vpngw-tun1"
    azure_public_ip      = azurerm_public_ip.vpngw_pip_1.ip_address
    psk                  = "Use vpn_shared_key variable"
    local_bgp_ip         = "169.254.21.5/30"
    remote_bgp_ip        = local.azure_bgp_ip_1
    remote_asn           = local.azure_bgp_asn
    advertise_networks   = ["192.168.0.0/16", "fd20:e:1::/48"]
  }
}

output "router_2_config" {
  description = "Configuration for on-prem router 2 to connect to Azure"
  value = var.enable_active_active ? {
    tunnel_name          = "azure-vpngw-tun2"
    azure_public_ip      = azurerm_public_ip.vpngw_pip_2[0].ip_address
    psk                  = "Use vpn_shared_key variable"
    local_bgp_ip         = "169.254.21.6/30"
    remote_bgp_ip        = local.azure_bgp_ip_2
    remote_asn           = local.azure_bgp_asn
    advertise_networks   = ["192.168.0.0/16", "fd20:e:1::/48"]
  } : null
}

# -----------------------------------------------------------------------------
# Connection Status Commands
# -----------------------------------------------------------------------------

output "check_connection_commands" {
  description = "Azure CLI commands to check VPN connection status"
  value = {
    connection_1_status = "az network vpn-connection show --name ${azurerm_virtual_network_gateway_connection.to_router_1.name} --resource-group ${azurerm_resource_group.main.name} --query connectionStatus -o tsv"
    connection_2_status = "az network vpn-connection show --name ${azurerm_virtual_network_gateway_connection.to_router_2.name} --resource-group ${azurerm_resource_group.main.name} --query connectionStatus -o tsv"
    learned_routes      = "az network vnet-gateway list-learned-routes --name ${azurerm_virtual_network_gateway.main.name} --resource-group ${azurerm_resource_group.main.name}"
  }
}
