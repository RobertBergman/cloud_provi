# =============================================================================
# Outputs for AWS Dual-Stack VPN Infrastructure
# =============================================================================
# Provides VPN configuration details for on-prem router setup
# Note: AWS requires separate VPN connections for IPv4 and IPv6 traffic
# =============================================================================

# =============================================================================
# IPv6 VPN - Router 1
# =============================================================================

output "vpn_router_1_ipv6_tunnel_1" {
  description = "IPv6 VPN tunnel 1 for router 1"
  value = {
    tunnel_name            = "aws-r1-v6-tun1"
    outside_ip             = aws_vpn_connection.router_1.tunnel1_address
    inside_ipv6_cidr       = aws_vpn_connection.router_1.tunnel1_inside_ipv6_cidr
    psk                    = aws_vpn_connection.router_1.tunnel1_preshared_key
    bgp_asn                = local.aws_asn
    traffic_selector       = "::/0"
  }
  sensitive = true
}

output "vpn_router_1_ipv6_tunnel_2" {
  description = "IPv6 VPN tunnel 2 for router 1"
  value = {
    tunnel_name            = "aws-r1-v6-tun2"
    outside_ip             = aws_vpn_connection.router_1.tunnel2_address
    inside_ipv6_cidr       = aws_vpn_connection.router_1.tunnel2_inside_ipv6_cidr
    psk                    = aws_vpn_connection.router_1.tunnel2_preshared_key
    bgp_asn                = local.aws_asn
    traffic_selector       = "::/0"
  }
  sensitive = true
}

# =============================================================================
# IPv4 VPN - Router 1
# =============================================================================

output "vpn_router_1_ipv4_tunnel_1" {
  description = "IPv4 VPN tunnel 1 for router 1"
  value = {
    tunnel_name       = "aws-r1-v4-tun1"
    outside_ip        = aws_vpn_connection.router_1_ipv4.tunnel1_address
    inside_ip_aws     = aws_vpn_connection.router_1_ipv4.tunnel1_vgw_inside_address
    inside_ip_onprem  = aws_vpn_connection.router_1_ipv4.tunnel1_cgw_inside_address
    psk               = aws_vpn_connection.router_1_ipv4.tunnel1_preshared_key
    bgp_asn           = local.aws_asn
    traffic_selector  = "0.0.0.0/0"
  }
  sensitive = true
}

output "vpn_router_1_ipv4_tunnel_2" {
  description = "IPv4 VPN tunnel 2 for router 1"
  value = {
    tunnel_name       = "aws-r1-v4-tun2"
    outside_ip        = aws_vpn_connection.router_1_ipv4.tunnel2_address
    inside_ip_aws     = aws_vpn_connection.router_1_ipv4.tunnel2_vgw_inside_address
    inside_ip_onprem  = aws_vpn_connection.router_1_ipv4.tunnel2_cgw_inside_address
    psk               = aws_vpn_connection.router_1_ipv4.tunnel2_preshared_key
    bgp_asn           = local.aws_asn
    traffic_selector  = "0.0.0.0/0"
  }
  sensitive = true
}

# =============================================================================
# IPv6 VPN - Router 2
# =============================================================================

output "vpn_router_2_ipv6_tunnel_1" {
  description = "IPv6 VPN tunnel 1 for router 2"
  value = {
    tunnel_name            = "aws-r2-v6-tun1"
    outside_ip             = aws_vpn_connection.router_2.tunnel1_address
    inside_ipv6_cidr       = aws_vpn_connection.router_2.tunnel1_inside_ipv6_cidr
    psk                    = aws_vpn_connection.router_2.tunnel1_preshared_key
    bgp_asn                = local.aws_asn
    traffic_selector       = "::/0"
  }
  sensitive = true
}

output "vpn_router_2_ipv6_tunnel_2" {
  description = "IPv6 VPN tunnel 2 for router 2"
  value = {
    tunnel_name            = "aws-r2-v6-tun2"
    outside_ip             = aws_vpn_connection.router_2.tunnel2_address
    inside_ipv6_cidr       = aws_vpn_connection.router_2.tunnel2_inside_ipv6_cidr
    psk                    = aws_vpn_connection.router_2.tunnel2_preshared_key
    bgp_asn                = local.aws_asn
    traffic_selector       = "::/0"
  }
  sensitive = true
}

# =============================================================================
# IPv4 VPN - Router 2
# =============================================================================

output "vpn_router_2_ipv4_tunnel_1" {
  description = "IPv4 VPN tunnel 1 for router 2"
  value = {
    tunnel_name       = "aws-r2-v4-tun1"
    outside_ip        = aws_vpn_connection.router_2_ipv4.tunnel1_address
    inside_ip_aws     = aws_vpn_connection.router_2_ipv4.tunnel1_vgw_inside_address
    inside_ip_onprem  = aws_vpn_connection.router_2_ipv4.tunnel1_cgw_inside_address
    psk               = aws_vpn_connection.router_2_ipv4.tunnel1_preshared_key
    bgp_asn           = local.aws_asn
    traffic_selector  = "0.0.0.0/0"
  }
  sensitive = true
}

output "vpn_router_2_ipv4_tunnel_2" {
  description = "IPv4 VPN tunnel 2 for router 2"
  value = {
    tunnel_name       = "aws-r2-v4-tun2"
    outside_ip        = aws_vpn_connection.router_2_ipv4.tunnel2_address
    inside_ip_aws     = aws_vpn_connection.router_2_ipv4.tunnel2_vgw_inside_address
    inside_ip_onprem  = aws_vpn_connection.router_2_ipv4.tunnel2_cgw_inside_address
    psk               = aws_vpn_connection.router_2_ipv4.tunnel2_preshared_key
    bgp_asn           = local.aws_asn
    traffic_selector  = "0.0.0.0/0"
  }
  sensitive = true
}

# =============================================================================
# AWS Resources Info
# =============================================================================

output "vpc_id" {
  description = "AWS VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_ipv4_cidr" {
  description = "AWS VPC IPv4 CIDR"
  value       = aws_vpc.main.cidr_block
}

output "vpc_ipv6_cidr" {
  description = "AWS VPC IPv6 CIDR"
  value       = aws_vpc.main.ipv6_cidr_block
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.main.id
}

output "test_instance_public_ip" {
  description = "Public IP of test EC2 instance"
  value       = aws_instance.test.public_ip
}

output "test_instance_private_ip" {
  description = "Private IP of test EC2 instance"
  value       = aws_instance.test.private_ip
}

output "test_instance_ipv6" {
  description = "IPv6 address of test EC2 instance"
  value       = aws_instance.test.ipv6_addresses
}

# =============================================================================
# Configuration Summary
# =============================================================================

output "vpn_summary" {
  description = "Summary of VPN connections"
  value = <<-EOT
    ============================================================
    AWS DUAL-STACK VPN SUMMARY
    ============================================================

    IMPORTANT: AWS requires separate VPN connections for IPv4 and IPv6.
    Each router needs 4 tunnels (2 IPv4 + 2 IPv6) for full redundancy.

    Router 1 Tunnels:
      IPv6: ${aws_vpn_connection.router_1.tunnel1_address}, ${aws_vpn_connection.router_1.tunnel2_address}
      IPv4: ${aws_vpn_connection.router_1_ipv4.tunnel1_address}, ${aws_vpn_connection.router_1_ipv4.tunnel2_address}

    Router 2 Tunnels:
      IPv6: ${aws_vpn_connection.router_2.tunnel1_address}, ${aws_vpn_connection.router_2.tunnel2_address}
      IPv4: ${aws_vpn_connection.router_2_ipv4.tunnel1_address}, ${aws_vpn_connection.router_2_ipv4.tunnel2_address}

    Total: 8 VPN tunnels (16 IPsec SAs)

    ============================================================
  EOT
}

output "router_config_instructions" {
  description = "Instructions for configuring on-prem routers"
  value = <<-EOT
    ============================================================
    ROUTER CONFIGURATION INSTRUCTIONS
    ============================================================

    For DUAL-STACK support, configure BOTH IPv4 and IPv6 tunnels:

    1. IPv6 Tunnels (traffic selector: ::/0)
       - Use configure-aws-ipv6-vpn.sh script
       - BGP over IPv6 inside addresses
       - Advertise IPv6 prefixes only

    2. IPv4 Tunnels (traffic selector: 0.0.0.0/0)
       - Use standard IPsec config (leftsubnet=0.0.0.0/0)
       - BGP over IPv4 inside addresses (169.254.x.x)
       - Advertise IPv4 prefixes only

    Each router will have:
       - 2 IPv6 tunnels (for IPv6 traffic)
       - 2 IPv4 tunnels (for IPv4 traffic)
       - 4 VTI interfaces total
       - 4 BGP neighbors (2 IPv6, 2 IPv4)

    Generate config files:
       terraform output -json vpn_router_1_ipv6_tunnel_1
       terraform output -json vpn_router_1_ipv4_tunnel_1
       # etc.

    ============================================================
  EOT
}
