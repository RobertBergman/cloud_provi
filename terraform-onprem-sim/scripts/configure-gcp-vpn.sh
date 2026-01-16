#!/bin/bash
# =============================================================================
# Configure GCP HA VPN Tunnel with Dual-Stack BGP
# =============================================================================
# Usage: ./configure-gcp-vpn.sh --config <json-file> --router-id <1|2>
#
# This script configures:
# - IPsec tunnel to GCP HA VPN Gateway
# - VTI interface with both IPv4 and IPv6 inside addresses
# - BGP sessions for both IPv4 and IPv6 (dedicated sessions, not MP-BGP)
#
# GCP HA VPN supports both IPv4 and IPv6 in a single tunnel, unlike AWS
# which requires separate VPN connections for each address family.
# =============================================================================

set -e

usage() {
    cat << EOF
Usage: $0 --config <file> --router-id <1|2>

Configure GCP HA VPN tunnel with dual-stack BGP.

Options:
  --config <file>     JSON config file with tunnel parameters
  --router-id <1|2>   Router ID (determines VTI numbering)
  --help              Show this help

JSON config format:
{
  "tunnels": [
    {
      "name": "gcp-tunnel-r1",
      "remote_ip": "GCP VPN Gateway public IP",
      "psk": "pre-shared-key",
      "local_inside_ip": "169.254.0.2",
      "remote_inside_ip": "169.254.0.1",
      "local_inside_ipv6": "fdff:1::2",
      "remote_inside_ipv6": "fdff:1::1",
      "remote_asn": 65515
    }
  ]
}
EOF
    exit 1
}

# Parse arguments
CONFIG_FILE=""
ROUTER_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --router-id) ROUTER_ID="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]] || [[ -z "$ROUTER_ID" ]]; then
    echo "Error: --config and --router-id are required"
    usage
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Get local IPs
LOCAL_PUBLIC_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google" 2>/dev/null || curl -s ifconfig.me)
LOCAL_PRIVATE_IP=$(hostname -I | awk '{print $1}')
BGP_ASN=$(grep -oP 'router bgp \K\d+' /etc/frr/frr.conf 2>/dev/null || echo "65001")

echo "=============================================="
echo "GCP HA VPN Configuration - Router $ROUTER_ID"
echo "=============================================="
echo "Local public IP:  $LOCAL_PUBLIC_IP"
echo "Local private IP: $LOCAL_PRIVATE_IP"
echo "BGP ASN:          $BGP_ASN"
echo ""

# VTI numbering: GCP tunnels use vti20+ to avoid conflicts with AWS (vti1-10)
VTI_START=20
MARK_START=200

configure_tunnel() {
    local CONFIG_FILE="$1"
    local TUNNEL_COUNT=$(jq '.tunnels | length' "$CONFIG_FILE")

    for i in $(seq 0 $((TUNNEL_COUNT - 1))); do
        local NAME=$(jq -r ".tunnels[$i].name" "$CONFIG_FILE")
        local REMOTE_IP=$(jq -r ".tunnels[$i].remote_ip" "$CONFIG_FILE")
        local PSK=$(jq -r ".tunnels[$i].psk" "$CONFIG_FILE")
        local LOCAL_V4=$(jq -r ".tunnels[$i].local_inside_ip" "$CONFIG_FILE")
        local REMOTE_V4=$(jq -r ".tunnels[$i].remote_inside_ip" "$CONFIG_FILE")
        local LOCAL_V6=$(jq -r ".tunnels[$i].local_inside_ipv6" "$CONFIG_FILE")
        local REMOTE_V6=$(jq -r ".tunnels[$i].remote_inside_ipv6" "$CONFIG_FILE")
        local REMOTE_ASN=$(jq -r ".tunnels[$i].remote_asn" "$CONFIG_FILE")

        local VTI_NUM=$((VTI_START + i))
        local VTI_NAME="vti${VTI_NUM}"
        local MARK=$((MARK_START + i))

        echo "=== Configuring $NAME ==="
        echo "  Remote IP:        $REMOTE_IP"
        echo "  Local BGP IPv4:   $LOCAL_V4"
        echo "  Remote BGP IPv4:  $REMOTE_V4"
        echo "  Local BGP IPv6:   $LOCAL_V6"
        echo "  Remote BGP IPv6:  $REMOTE_V6"
        echo "  VTI Interface:    $VTI_NAME"
        echo ""

        # =================================================================
        # IPsec Configuration
        # =================================================================
        # GCP HA VPN uses IKEv2 with both IPv4 and IPv6 traffic selectors
        # in a single tunnel (unlike AWS which needs separate connections)
        cat > "/etc/ipsec.d/${NAME}.conf" << EOF
conn ${NAME}
    authby=secret
    auto=start
    left=%defaultroute
    leftid=${LOCAL_PUBLIC_IP}
    right=${REMOTE_IP}
    type=tunnel
    ikev2=yes
    ike=aes256-sha256-modp2048
    esp=aes256-sha256
    ikelifetime=36000s
    salifetime=10800s
    keyingtries=%forever
    # Both IPv4 and IPv6 traffic selectors for dual-stack
    leftsubnet=0.0.0.0/0,::/0
    rightsubnet=0.0.0.0/0,::/0
    mark=${MARK}/0xffffffff
    vti-interface=${VTI_NAME}
    vti-routing=no
    dpddelay=10
    dpdtimeout=30
    dpdaction=restart_by_peer
EOF

        # Add PSK to secrets file
        if ! grep -q "$REMOTE_IP" /etc/ipsec.secrets 2>/dev/null; then
            echo "${LOCAL_PUBLIC_IP} ${REMOTE_IP} : PSK \"${PSK}\"" >> /etc/ipsec.secrets
        fi

        # =================================================================
        # VTI Interface Configuration
        # =================================================================
        # Delete existing VTI if present
        ip link del "$VTI_NAME" 2>/dev/null || true

        # Create VTI tunnel
        ip tunnel add "$VTI_NAME" local "$LOCAL_PRIVATE_IP" remote "$REMOTE_IP" mode vti key "$MARK"

        # Add BOTH IPv4 and IPv6 addresses to VTI
        ip addr add "${LOCAL_V4}/30" dev "$VTI_NAME"
        ip -6 addr add "${LOCAL_V6}/126" dev "$VTI_NAME"

        # Bring interface up with appropriate MTU
        ip link set "$VTI_NAME" up mtu 1400

        # Disable reverse path filtering for IPsec
        sysctl -w "net.ipv4.conf.${VTI_NAME}.disable_policy=1" > /dev/null
        sysctl -w "net.ipv4.conf.${VTI_NAME}.rp_filter=0" > /dev/null

        # =================================================================
        # BGP Configuration - IPv4 Neighbor
        # =================================================================
        echo "Configuring IPv4 BGP neighbor..."
        vtysh -c "configure terminal" \
              -c "router bgp ${BGP_ASN}" \
              -c "neighbor ${REMOTE_V4} remote-as ${REMOTE_ASN}" \
              -c "neighbor ${REMOTE_V4} description ${NAME}-v4" \
              -c "neighbor ${REMOTE_V4} ebgp-multihop 2" \
              -c "address-family ipv4 unicast" \
              -c "neighbor ${REMOTE_V4} activate" \
              -c "neighbor ${REMOTE_V4} soft-reconfiguration inbound" \
              -c "exit-address-family" \
              -c "exit" -c "exit" -c "write memory" 2>/dev/null

        # =================================================================
        # BGP Configuration - IPv6 Neighbor (DEDICATED SESSION)
        # =================================================================
        # CRITICAL: GCP requires dedicated IPv6 BGP sessions for proper
        # IPv6 route installation. MP-BGP (enable_ipv6 on IPv4 peers)
        # does NOT work for route installation in GCP.
        echo "Configuring IPv6 BGP neighbor (dedicated session)..."
        vtysh -c "configure terminal" \
              -c "router bgp ${BGP_ASN}" \
              -c "neighbor ${REMOTE_V6} remote-as ${REMOTE_ASN}" \
              -c "neighbor ${REMOTE_V6} description ${NAME}-v6" \
              -c "neighbor ${REMOTE_V6} ebgp-multihop 2" \
              -c "address-family ipv6 unicast" \
              -c "neighbor ${REMOTE_V6} activate" \
              -c "neighbor ${REMOTE_V6} soft-reconfiguration inbound" \
              -c "exit-address-family" \
              -c "exit" -c "exit" -c "write memory" 2>/dev/null

        echo "Tunnel $NAME configured successfully"
        echo ""
    done
}

# Main execution
configure_tunnel "$CONFIG_FILE"

# Restart IPsec to apply new configuration
echo "=== Restarting IPsec ==="
systemctl restart ipsec
sleep 10

# Show status
echo ""
echo "=== IPsec Status ==="
ipsec status | grep -E "ESTABLISHED|STATE" || echo "Waiting for tunnels to establish..."

echo ""
echo "=== BGP Summary ==="
vtysh -c "show bgp summary"

echo ""
echo "=== IPv4 Routes Learned ==="
vtysh -c "show bgp ipv4 unicast" | head -20

echo ""
echo "=== IPv6 Routes Learned ==="
vtysh -c "show bgp ipv6 unicast" | head -20

echo ""
echo "=============================================="
echo "Configuration complete!"
echo ""
echo "Test commands:"
echo "  ping <gcp-test-vm-ipv4>      # IPv4 test"
echo "  ping6 <gcp-test-vm-ipv6>     # IPv6 test"
echo "  sudo vpn-status.sh           # Full status"
echo "=============================================="
