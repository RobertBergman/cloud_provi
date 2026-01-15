#!/bin/bash
# =============================================================================
# Configure Azure VPN Gateway Tunnels
# =============================================================================
# Usage: ./configure-azure-vpn.sh --config <file>
#
# This script configures IPsec tunnels to Azure VPN Gateway.
# Azure VPN Gateway uses APIPA addresses (169.254.x.x) for BGP peering.
# =============================================================================

set -e

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure Azure VPN Gateway IPsec tunnels.

Options:
  --config <file>      JSON config file with tunnel details
  --router-id <1|2>    Router ID (determines VTI numbering and BGP peer IP)
  --help               Show this help

JSON config format:
{
  "tunnels": [
    {
      "name": "azure-vpngw-tun1",
      "remote_ip": "Azure VPN Gateway public IP",
      "psk": "pre-shared-key",
      "local_bgp_ip": "169.254.21.5",
      "remote_bgp_ip": "169.254.21.1",
      "remote_asn": 65515
    }
  ]
}

Example:
  $0 --config azure-vpn-config.json --router-id 1
EOF
    exit 1
}

# Parse arguments
CONFIG_FILE=""
ROUTER_ID="1"

while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --router-id) ROUTER_ID="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: --config is required"
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
echo "Azure VPN Gateway Configuration"
echo "=============================================="
echo "Router ID: $ROUTER_ID"
echo "Local public IP: $LOCAL_PUBLIC_IP"
echo "Local private IP: $LOCAL_PRIVATE_IP"
echo "BGP ASN: $BGP_ASN"
echo ""

# VTI numbering: Azure tunnels start at vti10 to not conflict with AWS (vti1-4)
VTI_START=10

configure_tunnels() {
    local CONFIG_FILE="$1"

    local TUNNEL_COUNT=$(jq '.tunnels | length' "$CONFIG_FILE")
    echo "Configuring $TUNNEL_COUNT tunnel(s)..."

    for i in $(seq 0 $((TUNNEL_COUNT - 1))); do
        local NAME=$(jq -r ".tunnels[$i].name" "$CONFIG_FILE")
        local REMOTE_IP=$(jq -r ".tunnels[$i].remote_ip" "$CONFIG_FILE")
        local PSK=$(jq -r ".tunnels[$i].psk" "$CONFIG_FILE")
        local LOCAL_BGP_IP=$(jq -r ".tunnels[$i].local_bgp_ip" "$CONFIG_FILE")
        local REMOTE_BGP_IP=$(jq -r ".tunnels[$i].remote_bgp_ip" "$CONFIG_FILE")
        local REMOTE_ASN=$(jq -r ".tunnels[$i].remote_asn" "$CONFIG_FILE")

        local VTI_NUM=$((VTI_START + i))
        local VTI_NAME="vti${VTI_NUM}"
        local MARK=$((300 + i))  # Marks 300+ for Azure to not conflict with AWS

        echo ""
        echo "=== Configuring $NAME -> $VTI_NAME ==="
        echo "  Remote IP: $REMOTE_IP"
        echo "  Local BGP: $LOCAL_BGP_IP"
        echo "  Remote BGP: $REMOTE_BGP_IP"
        echo "  Remote ASN: $REMOTE_ASN"

        # IPsec config - Azure uses IKEv2 with specific proposals
        cat > "/etc/ipsec.d/${NAME}.conf" << EOF
conn ${NAME}
    authby=secret
    auto=start
    left=%defaultroute
    leftid=${LOCAL_PUBLIC_IP}
    right=${REMOTE_IP}
    type=tunnel
    ikev2=yes
    ikelifetime=28800s
    salifetime=3600s
    ike=aes256-sha256-modp2048
    esp=aes256-sha256
    keyingtries=%forever
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=${MARK}/0xffffffff
    vti-interface=${VTI_NAME}
    vti-routing=no
    dpddelay=10
    dpdtimeout=30
    dpdaction=restart_by_peer
EOF

        # Add PSK if not already present
        if ! grep -q "$REMOTE_IP" /etc/ipsec.secrets 2>/dev/null; then
            echo "%any ${REMOTE_IP} : PSK \"${PSK}\"" >> /etc/ipsec.secrets
        fi

        # Create VTI interface
        ip link del "$VTI_NAME" 2>/dev/null || true
        ip tunnel add "$VTI_NAME" local "$LOCAL_PRIVATE_IP" remote "$REMOTE_IP" mode vti key "$MARK"

        # Add BGP peering IP to VTI interface (APIPA address)
        ip addr add "${LOCAL_BGP_IP}/30" dev "$VTI_NAME"

        # Add on-prem source IP for return traffic identification
        ip addr add "${LOCAL_PRIVATE_IP}/32" dev "$VTI_NAME" 2>/dev/null || true

        # Bring up VTI
        ip link set "$VTI_NAME" up mtu 1400

        # Disable reverse path filtering for VTI
        sysctl -w "net.ipv4.conf.${VTI_NAME}.disable_policy=1" > /dev/null
        sysctl -w "net.ipv4.conf.${VTI_NAME}.rp_filter=0" > /dev/null

        # Configure BGP neighbor in FRR
        echo "Configuring BGP neighbor..."
        vtysh -c "configure terminal" \
              -c "router bgp ${BGP_ASN}" \
              -c "neighbor ${REMOTE_BGP_IP} remote-as ${REMOTE_ASN}" \
              -c "neighbor ${REMOTE_BGP_IP} description ${NAME}" \
              -c "neighbor ${REMOTE_BGP_IP} ebgp-multihop 255" \
              -c "neighbor ${REMOTE_BGP_IP} update-source ${LOCAL_BGP_IP}" \
              -c "address-family ipv4 unicast" \
              -c "neighbor ${REMOTE_BGP_IP} activate" \
              -c "neighbor ${REMOTE_BGP_IP} soft-reconfiguration inbound" \
              -c "exit-address-family" \
              -c "exit" -c "exit" -c "write memory" 2>/dev/null || echo "Note: BGP config may need manual review"

        echo "Tunnel $NAME configured"
    done
}

# Main
echo "=== Configuring Azure VPN Tunnels ==="
configure_tunnels "$CONFIG_FILE"

# Restart IPsec
echo ""
echo "=== Restarting IPsec ==="
systemctl restart ipsec
sleep 10

# Show status
echo ""
echo "=== IPsec Status ==="
ipsec status | grep -E "ESTABLISHED|STATE" || echo "Waiting for tunnels to establish..."

echo ""
echo "=== BGP Summary ==="
vtysh -c "show bgp summary" 2>/dev/null || echo "BGP not ready yet"

echo ""
echo "=============================================="
echo "Configuration complete!"
echo ""
echo "To check status later, run: vpn-status.sh"
echo ""
echo "To test connectivity from on-prem test VM:"
echo "  ping <azure-test-vm-ipv4>    # IPv4"
echo "  ping6 <azure-test-vm-ipv6>   # IPv6"
echo "=============================================="
