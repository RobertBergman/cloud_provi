#!/bin/bash
# =============================================================================
# Configure AWS VPN Tunnels (Both IPv4 and IPv6)
# =============================================================================
# Usage: ./configure-aws-vpn.sh --ipv4-config <file> --ipv6-config <file>
#
# This script configures both IPv4 and IPv6 VPN tunnels for AWS Transit Gateway.
# AWS requires separate VPN connections for each address family.
# =============================================================================

set -e

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure AWS Site-to-Site VPN tunnels (dual-stack).

Options:
  --ipv4-config <file>   JSON config for IPv4 tunnels
  --ipv6-config <file>   JSON config for IPv6 tunnels
  --router-id <1|2>      Router ID (determines VTI numbering)
  --help                 Show this help

JSON config format:
{
  "tunnels": [
    {
      "name": "aws-r1-v4-tun1",
      "remote_ip": "52.x.x.x",
      "psk": "secret",
      "local_inside_ip": "169.254.x.x",
      "remote_inside_ip": "169.254.x.x",
      "remote_asn": 64512
    }
  ]
}

For IPv6 tunnels, add:
  "local_inside_ipv6": "fdxx::2",
  "remote_inside_ipv6": "fdxx::1"
EOF
    exit 1
}

# Parse arguments
IPV4_CONFIG=""
IPV6_CONFIG=""
ROUTER_ID="1"

while [[ $# -gt 0 ]]; do
    case $1 in
        --ipv4-config) IPV4_CONFIG="$2"; shift 2 ;;
        --ipv6-config) IPV6_CONFIG="$2"; shift 2 ;;
        --router-id) ROUTER_ID="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Get local IPs
LOCAL_PUBLIC_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google" 2>/dev/null || curl -s ifconfig.me)
LOCAL_PRIVATE_IP=$(hostname -I | awk '{print $1}')
BGP_ASN=$(grep -oP 'router bgp \K\d+' /etc/frr/frr.conf 2>/dev/null || echo "65001")

echo "=============================================="
echo "AWS Dual-Stack VPN Configuration"
echo "=============================================="
echo "Router ID: $ROUTER_ID"
echo "Local public IP: $LOCAL_PUBLIC_IP"
echo "Local private IP: $LOCAL_PRIVATE_IP"
echo "BGP ASN: $BGP_ASN"
echo ""

configure_ipv6_tunnels() {
    local CONFIG_FILE="$1"
    local VTI_START=1

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "IPv6 config file not found: $CONFIG_FILE"
        return 1
    fi

    echo "=== Configuring IPv6 Tunnels ==="

    local TUNNEL_COUNT=$(jq '.tunnels | length' "$CONFIG_FILE")

    for i in $(seq 0 $((TUNNEL_COUNT - 1))); do
        local NAME=$(jq -r ".tunnels[$i].name" "$CONFIG_FILE")
        local REMOTE_IP=$(jq -r ".tunnels[$i].remote_ip" "$CONFIG_FILE")
        local PSK=$(jq -r ".tunnels[$i].psk" "$CONFIG_FILE")
        local LOCAL_INSIDE=$(jq -r ".tunnels[$i].local_inside_ip" "$CONFIG_FILE")
        local REMOTE_INSIDE=$(jq -r ".tunnels[$i].remote_inside_ip" "$CONFIG_FILE")
        local LOCAL_INSIDE_V6=$(jq -r ".tunnels[$i].local_inside_ipv6" "$CONFIG_FILE")
        local REMOTE_INSIDE_V6=$(jq -r ".tunnels[$i].remote_inside_ipv6" "$CONFIG_FILE")
        local REMOTE_ASN=$(jq -r ".tunnels[$i].remote_asn" "$CONFIG_FILE")

        local VTI_NUM=$((VTI_START + i))
        local VTI_NAME="vti${VTI_NUM}"
        local MARK=$((100 + i))

        echo "Configuring $NAME -> $VTI_NAME"

        # IPsec config with IPv6 traffic selectors
        cat > "/etc/ipsec.d/${NAME}.conf" << EOF
conn ${NAME}
    authby=secret
    auto=start
    left=%defaultroute
    leftid=${LOCAL_PUBLIC_IP}
    right=${REMOTE_IP}
    type=tunnel
    ikelifetime=8h
    keylife=1h
    phase2alg=aes256-sha256
    ike=aes256-sha256-modp2048
    keyingtries=%forever
    leftsubnet=::/0
    rightsubnet=::/0
    mark=${MARK}/0xffffffff
    vti-interface=${VTI_NAME}
    vti-routing=no
    leftvti=${LOCAL_INSIDE}/30
    dpddelay=10
    dpdtimeout=30
    dpdaction=restart_by_peer
EOF

        # Add PSK
        if ! grep -q "$REMOTE_IP" /etc/ipsec.secrets 2>/dev/null; then
            echo "%any ${REMOTE_IP} : PSK \"${PSK}\"" >> /etc/ipsec.secrets
        fi

        # Create VTI interface
        ip link del "$VTI_NAME" 2>/dev/null || true
        ip tunnel add "$VTI_NAME" local "$LOCAL_PRIVATE_IP" remote "$REMOTE_IP" mode vti key "$MARK"
        ip addr add "${LOCAL_INSIDE}/30" dev "$VTI_NAME"

        if [[ "$LOCAL_INSIDE_V6" != "null" ]]; then
            ip -6 addr add "${LOCAL_INSIDE_V6}/126" dev "$VTI_NAME"
        fi

        # Add on-prem source IPv6
        ip -6 addr add "fd20:e:1::${ROUTER_ID}/128" dev "$VTI_NAME" 2>/dev/null || true

        ip link set "$VTI_NAME" up mtu 1419
        sysctl -w "net.ipv4.conf.${VTI_NAME}.disable_policy=1" > /dev/null
        sysctl -w "net.ipv4.conf.${VTI_NAME}.rp_filter=0" > /dev/null

        # Add BGP neighbor (IPv6)
        if [[ "$REMOTE_INSIDE_V6" != "null" ]]; then
            vtysh -c "configure terminal" \
                  -c "router bgp ${BGP_ASN}" \
                  -c "neighbor ${REMOTE_INSIDE_V6} remote-as ${REMOTE_ASN}" \
                  -c "neighbor ${REMOTE_INSIDE_V6} description ${NAME}" \
                  -c "address-family ipv6 unicast" \
                  -c "neighbor ${REMOTE_INSIDE_V6} activate" \
                  -c "neighbor ${REMOTE_INSIDE_V6} next-hop-self" \
                  -c "exit-address-family" \
                  -c "exit" -c "exit" -c "write memory" 2>/dev/null
        fi
    done
}

configure_ipv4_tunnels() {
    local CONFIG_FILE="$1"
    local VTI_START=3  # Start at vti3 for IPv4 (vti1/vti2 for IPv6)

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "IPv4 config file not found: $CONFIG_FILE"
        return 1
    fi

    echo "=== Configuring IPv4 Tunnels ==="

    local TUNNEL_COUNT=$(jq '.tunnels | length' "$CONFIG_FILE")

    for i in $(seq 0 $((TUNNEL_COUNT - 1))); do
        local NAME=$(jq -r ".tunnels[$i].name" "$CONFIG_FILE")
        local REMOTE_IP=$(jq -r ".tunnels[$i].remote_ip" "$CONFIG_FILE")
        local PSK=$(jq -r ".tunnels[$i].psk" "$CONFIG_FILE")
        local LOCAL_INSIDE=$(jq -r ".tunnels[$i].local_inside_ip" "$CONFIG_FILE")
        local REMOTE_INSIDE=$(jq -r ".tunnels[$i].remote_inside_ip" "$CONFIG_FILE")
        local REMOTE_ASN=$(jq -r ".tunnels[$i].remote_asn" "$CONFIG_FILE")

        local VTI_NUM=$((VTI_START + i))
        local VTI_NAME="vti${VTI_NUM}"
        local MARK=$((200 + i))

        echo "Configuring $NAME -> $VTI_NAME"

        # IPsec config with IPv4 traffic selectors
        cat > "/etc/ipsec.d/${NAME}.conf" << EOF
conn ${NAME}
    authby=secret
    auto=start
    left=%defaultroute
    leftid=${LOCAL_PUBLIC_IP}
    right=${REMOTE_IP}
    type=tunnel
    ikelifetime=8h
    keylife=1h
    phase2alg=aes256-sha256
    ike=aes256-sha256-modp2048
    keyingtries=%forever
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=${MARK}/0xffffffff
    vti-interface=${VTI_NAME}
    vti-routing=no
    leftvti=${LOCAL_INSIDE}/30
    dpddelay=10
    dpdtimeout=30
    dpdaction=restart_by_peer
EOF

        # Add PSK
        if ! grep -q "$REMOTE_IP" /etc/ipsec.secrets 2>/dev/null; then
            echo "%any ${REMOTE_IP} : PSK \"${PSK}\"" >> /etc/ipsec.secrets
        fi

        # Create VTI interface
        ip link del "$VTI_NAME" 2>/dev/null || true
        ip tunnel add "$VTI_NAME" local "$LOCAL_PRIVATE_IP" remote "$REMOTE_IP" mode vti key "$MARK"
        ip addr add "${LOCAL_INSIDE}/30" dev "$VTI_NAME"
        ip link set "$VTI_NAME" up mtu 1419
        sysctl -w "net.ipv4.conf.${VTI_NAME}.disable_policy=1" > /dev/null
        sysctl -w "net.ipv4.conf.${VTI_NAME}.rp_filter=0" > /dev/null

        # Add BGP neighbor (IPv4)
        vtysh -c "configure terminal" \
              -c "router bgp ${BGP_ASN}" \
              -c "neighbor ${REMOTE_INSIDE} remote-as ${REMOTE_ASN}" \
              -c "neighbor ${REMOTE_INSIDE} description ${NAME}" \
              -c "neighbor ${REMOTE_INSIDE} ebgp-multihop 255" \
              -c "neighbor ${REMOTE_INSIDE} update-source ${LOCAL_INSIDE}" \
              -c "address-family ipv4 unicast" \
              -c "neighbor ${REMOTE_INSIDE} activate" \
              -c "exit-address-family" \
              -c "exit" -c "exit" -c "write memory" 2>/dev/null
    done
}

# Main
if [[ -n "$IPV6_CONFIG" ]]; then
    configure_ipv6_tunnels "$IPV6_CONFIG"
fi

if [[ -n "$IPV4_CONFIG" ]]; then
    configure_ipv4_tunnels "$IPV4_CONFIG"
fi

# Restart IPsec
echo ""
echo "=== Restarting IPsec ==="
systemctl restart ipsec
sleep 10

# Show status
echo ""
echo "=== VPN Status ==="
ipsec status | grep -E "ESTABLISHED|STATE_V2_IPSEC"
echo ""
echo "=== BGP Summary ==="
vtysh -c "show bgp summary"
