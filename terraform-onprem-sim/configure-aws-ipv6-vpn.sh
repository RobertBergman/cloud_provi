#!/bin/bash
# =============================================================================
# Configure AWS IPv6 VPN Tunnel
# =============================================================================
# For AWS Transit Gateway VPN with tunnel_inside_ip_version = "ipv6"
#
# AWS IPv6 VPN requires:
# - IPv6 traffic selectors (::/0) instead of IPv4 (0.0.0.0/0)
# - VTI interface with both IPv4 and IPv6 inside addresses
# - BGP over IPv6 inside addresses
# =============================================================================

set -e

# Usage info
usage() {
    cat << EOF
Usage: $0 --config <json-file>

Configure an AWS VPN tunnel with IPv6 support.

JSON config format:
{
  "tunnels": [
    {
      "name": "aws-r1-tun1",
      "remote_ip": "13.223.253.128",
      "psk": "secret123",
      "local_inside_ip": "169.254.47.206",
      "remote_inside_ip": "169.254.47.205",
      "local_inside_ipv6": "fd0a:8229:3c32:9e:73c3:ca48:e7b7:b182",
      "remote_inside_ipv6": "fd0a:8229:3c32:9e:73c3:ca48:e7b7:b181",
      "remote_asn": 64512
    }
  ]
}

After running this script:
1. IPsec tunnels will be configured with IPv6 traffic selectors
2. VTI interfaces will have both IPv4 and IPv6 addresses
3. BGP sessions will be established over IPv6

Note: Get the IPv6 inside addresses from the AWS VPN connection details
or terraform outputs.
EOF
    exit 1
}

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Parse arguments
CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --config|-c)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -f "$1" ]]; then
                CONFIG_FILE="$1"
                shift
            else
                echo "Unknown option: $1"
                usage
            fi
            ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: Config file required"
    usage
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Get local public IP
LOCAL_PUBLIC_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google" 2>/dev/null || curl -s ifconfig.me)
LOCAL_PRIVATE_IP=$(hostname -I | awk '{print $1}')

echo "=============================================="
echo "AWS IPv6 VPN Configuration"
echo "=============================================="
echo "Local public IP:  $LOCAL_PUBLIC_IP"
echo "Local private IP: $LOCAL_PRIVATE_IP"
echo ""

# Process each tunnel
TUNNEL_COUNT=$(jq '.tunnels | length' "$CONFIG_FILE")
echo "Found $TUNNEL_COUNT tunnel(s) to configure"
echo ""

for i in $(seq 0 $((TUNNEL_COUNT - 1))); do
    NAME=$(jq -r ".tunnels[$i].name" "$CONFIG_FILE")
    REMOTE_IP=$(jq -r ".tunnels[$i].remote_ip" "$CONFIG_FILE")
    PSK=$(jq -r ".tunnels[$i].psk" "$CONFIG_FILE")
    LOCAL_INSIDE=$(jq -r ".tunnels[$i].local_inside_ip" "$CONFIG_FILE")
    REMOTE_INSIDE=$(jq -r ".tunnels[$i].remote_inside_ip" "$CONFIG_FILE")
    LOCAL_INSIDE_V6=$(jq -r ".tunnels[$i].local_inside_ipv6" "$CONFIG_FILE")
    REMOTE_INSIDE_V6=$(jq -r ".tunnels[$i].remote_inside_ipv6" "$CONFIG_FILE")
    REMOTE_ASN=$(jq -r ".tunnels[$i].remote_asn" "$CONFIG_FILE")

    echo "----------------------------------------------"
    echo "Configuring tunnel: $NAME"
    echo "  Remote endpoint: $REMOTE_IP"
    echo "  Local inside IPv4: $LOCAL_INSIDE"
    echo "  Remote inside IPv4: $REMOTE_INSIDE"
    echo "  Local inside IPv6: $LOCAL_INSIDE_V6"
    echo "  Remote inside IPv6: $REMOTE_INSIDE_V6"
    echo "  Remote ASN: $REMOTE_ASN"
    echo ""

    # Determine VTI interface name and mark
    VTI_NUM=$((i + 1))
    VTI_NAME="vti${VTI_NUM}"
    MARK=$((100 + i))

    # Create IPsec config with IPv6 traffic selectors
    echo "Creating IPsec config: /etc/ipsec.d/${NAME}.conf"
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
    # IPv6 traffic selectors (required for AWS tunnel_inside_ip_version=ipv6)
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

    # Add PSK to secrets
    if ! grep -q "$REMOTE_IP" /etc/ipsec.secrets 2>/dev/null; then
        echo "${LOCAL_PUBLIC_IP} ${REMOTE_IP} : PSK \"${PSK}\"" >> /etc/ipsec.secrets
        echo "Added PSK to /etc/ipsec.secrets"
    fi

    # Delete existing VTI interface if exists
    if ip link show "$VTI_NAME" &>/dev/null; then
        echo "Removing existing $VTI_NAME interface"
        ip link del "$VTI_NAME" 2>/dev/null || true
    fi

    # Create VTI interface
    echo "Creating VTI interface: $VTI_NAME"
    ip tunnel add "$VTI_NAME" local "$LOCAL_PRIVATE_IP" remote "$REMOTE_IP" mode vti key "$MARK"
    ip addr add "${LOCAL_INSIDE}/30" dev "$VTI_NAME"
    ip -6 addr add "${LOCAL_INSIDE_V6}/126" dev "$VTI_NAME"
    ip link set "$VTI_NAME" up
    ip link set "$VTI_NAME" mtu 1419

    # Disable reverse path filtering on VTI
    sysctl -w "net.ipv4.conf.${VTI_NAME}.disable_policy=1" > /dev/null
    sysctl -w "net.ipv4.conf.${VTI_NAME}.rp_filter=0" > /dev/null

    echo "VTI interface $VTI_NAME created"
    echo ""
done

# Restart IPsec
echo "----------------------------------------------"
echo "Restarting IPsec service..."
systemctl restart ipsec
sleep 3

# Configure BGP neighbors
echo ""
echo "Configuring BGP neighbors..."
BGP_ASN=$(vtysh -c "show running-config" | grep "router bgp" | awk '{print $3}')

for i in $(seq 0 $((TUNNEL_COUNT - 1))); do
    NAME=$(jq -r ".tunnels[$i].name" "$CONFIG_FILE")
    REMOTE_INSIDE_V6=$(jq -r ".tunnels[$i].remote_inside_ipv6" "$CONFIG_FILE")
    REMOTE_ASN=$(jq -r ".tunnels[$i].remote_asn" "$CONFIG_FILE")

    echo "Adding BGP neighbor: $REMOTE_INSIDE_V6 (ASN $REMOTE_ASN)"

    vtysh << EOF
configure terminal
router bgp ${BGP_ASN}
neighbor ${REMOTE_INSIDE_V6} remote-as ${REMOTE_ASN}
neighbor ${REMOTE_INSIDE_V6} description ${NAME}
address-family ipv6 unicast
neighbor ${REMOTE_INSIDE_V6} activate
neighbor ${REMOTE_INSIDE_V6} next-hop-self
exit-address-family
exit
exit
write memory
EOF
done

echo ""
echo "=============================================="
echo "Configuration complete!"
echo "=============================================="
echo ""
echo "Check status with:"
echo "  sudo ipsec status"
echo "  sudo vtysh -c 'show bgp summary'"
echo "  sudo vtysh -c 'show bgp ipv6 unicast'"
echo ""
