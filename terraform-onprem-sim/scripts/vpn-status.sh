#!/bin/bash
# =============================================================================
# VPN Status - Shows IPsec tunnels and BGP sessions
# =============================================================================

echo "=============================================="
echo "         VPN ROUTER STATUS"
echo "=============================================="
echo ""

echo "=== IPsec Tunnel Status ==="
ipsec status | grep -E "ESTABLISHED|STATE_V2_IPSEC" || echo "No established tunnels"
echo ""

echo "=== IPsec SA Details ==="
ipsec status | grep "Traffic:" || echo "No traffic stats"
echo ""

echo "=== BGP Summary ==="
vtysh -c "show bgp summary" 2>/dev/null || echo "FRR/BGP not running"
echo ""

echo "=== IPv4 Routes Learned ==="
vtysh -c "show bgp ipv4 unicast" 2>/dev/null | head -20
echo ""

echo "=== IPv6 Routes Learned ==="
vtysh -c "show bgp ipv6 unicast" 2>/dev/null | head -20
echo ""

echo "=== VTI Interfaces ==="
ip link show type vti 2>/dev/null | grep -E "^[0-9]+:|inet" || echo "No VTI interfaces"
echo ""

echo "=== Kernel Routes (via VPN) ==="
echo "IPv4:"
ip route show | grep -E "proto bgp|vti" | head -10
echo "IPv6:"
ip -6 route show | grep -E "proto bgp|vti" | head -10
echo ""

echo "=============================================="
