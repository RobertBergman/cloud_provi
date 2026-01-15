# Cloud Provider Dual-Stack VPN Infrastructure

Terraform infrastructure for deploying **dual-stack (IPv4 + IPv6) VPN connectivity** across Azure, GCP, and AWS. This project evaluates and implements cross-premises IPv6 connectivity using each cloud provider's native VPN services.

## Project Status Summary

| Cloud Provider | IPv4 VPN | IPv6 VPN | Status | Viable |
|----------------|----------|----------|--------|--------|
| **GCP** | ✅ Working | ✅ Working | Complete | ✅ **Yes** |
| **AWS** | ✅ Working | ✅ Working | Complete | ✅ **Yes** |
| **Azure** | ❌ Failed | ❌ Not Supported | Blocked | ❌ **No** |

---

## Quick Start

### Prerequisites

- Terraform >= 1.0
- Cloud CLI tools: `gcloud`, `aws`, `az`
- GitHub CLI: `gh` (optional)

### GCP (Recommended - Fastest Deployment)

```bash
cd terraform-gcp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**Deployment time:** ~3 minutes

### AWS

```bash
# 1. Deploy on-prem simulation (GCP-hosted routers)
cd terraform-onprem-sim
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

# 2. Deploy AWS infrastructure
cd ../terraform-aws
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

# 3. Configure routers with AWS tunnel details
# SSH to routers and run configure-aws-ipv6-vpn.sh
```

**Deployment time:** ~5 minutes

### Azure (IPv6 Not Supported)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

**Note:** Azure Virtual WAN S2S VPN does not support IPv6. Deployment will work but only IPv4 traffic will traverse the tunnel.

---

## Detailed Documentation

| Document | Description |
|----------|-------------|
| [GCP Dual-Stack VPN Solution](docs/gcp-dual-stack-vpn-solution.pdf) | Complete guide for GCP HA VPN with IPv6 |
| [AWS Dual-Stack VPN Solution](docs/aws-dual-stack-vpn.pdf) | AWS Transit Gateway VPN with IPv6 |

---

## Architecture Overview

### GCP: HA VPN with Dedicated IPv6 BGP Sessions

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GCP Cloud                                    │
│  ┌─────────────────┐              ┌─────────────────┐               │
│  │  vpc-cloud-prod │              │ vpc-onprem-prod │               │
│  │  10.0.0.0/16    │              │ 192.168.0.0/16  │               │
│  │  fd20:a:1::/48  │              │ fd20:b:1::/48   │               │
│  └────────┬────────┘              └────────┬────────┘               │
│           │                                │                         │
│  ┌────────┴────────┐              ┌────────┴────────┐               │
│  │ HA VPN Gateway  │◄────────────►│ HA VPN Gateway  │               │
│  │ (IPV4_IPV6)     │  4 Tunnels   │ (IPV4_IPV6)     │               │
│  └─────────────────┘              └─────────────────┘               │
│                                                                      │
│  BGP Sessions:                                                       │
│  • IPv4: 169.254.x.x ──► IPv4 routes                                │
│  • IPv6: fdff:1::x   ──► IPv6 routes (dedicated sessions)           │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Finding:** GCP's MP-BGP (`enable_ipv6=true` on IPv4 sessions) does not properly install IPv6 routes. The solution is to create **dedicated IPv6 BGP sessions** using a separate ULA range (`fdff:1::/64`) for BGP peering addresses.

**Test Results:**
- IPv4 ping: ✅ 32ms, 0% packet loss
- IPv6 ping: ✅ 33ms, 0% packet loss

### AWS: Transit Gateway with Separate IPv4/IPv6 VPN Connections

```
┌─────────────────────────────────────────────────────────────────────┐
│                           AWS Cloud                                  │
│  ┌─────────────────┐                                                │
│  │   Dual-Stack    │                                                │
│  │      VPC        │                                                │
│  │  10.0.0.0/16    │                                                │
│  │  2600:1f18::/56 │                                                │
│  └────────┬────────┘                                                │
│           │                                                          │
│  ┌────────┴────────┐                                                │
│  │ Transit Gateway │                                                │
│  │   ASN 64512     │                                                │
│  └────────┬────────┘                                                │
│           │                                                          │
│  ┌────────┴────────────────────────────┐                            │
│  │         VPN Connections             │                            │
│  │  ┌──────────┐      ┌──────────┐     │                            │
│  │  │  IPv4    │      │  IPv6    │     │                            │
│  │  │ 0.0.0.0/0│      │  ::/0    │     │                            │
│  │  └────┬─────┘      └────┬─────┘     │                            │
│  └───────┼─────────────────┼───────────┘                            │
│          │                 │                                         │
└──────────┼─────────────────┼────────────────────────────────────────┘
           │                 │
           ▼                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│              GCP-Hosted On-Prem Simulation                          │
│  ┌─────────────────┐      ┌─────────────────┐                       │
│  │   Router VM 1   │      │   Router VM 2   │                       │
│  │  FreeSwan + FRR │      │  FreeSwan + FRR │                       │
│  │  ASN 65001      │      │  ASN 65001      │                       │
│  └─────────────────┘      └─────────────────┘                       │
│                                                                      │
│  IPsec Tunnels:                                                      │
│  • IPv4 tunnel: leftsubnet=0.0.0.0/0, rightsubnet=0.0.0.0/0        │
│  • IPv6 tunnel: leftsubnet=::/0, rightsubnet=::/0                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Finding:** AWS Site-to-Site VPN does **not** support true dual-stack in a single tunnel. You must create **separate VPN connections** for IPv4 and IPv6 traffic:
- IPv4 VPN: `tunnel_inside_ip_version = "ipv4"` → Traffic selectors: `0.0.0.0/0`
- IPv6 VPN: `tunnel_inside_ip_version = "ipv6"` → Traffic selectors: `::/0`

**Test Results:**
- IPv4 ping: ✅ Working (requires separate IPv4 VPN connection)
- IPv6 ping: ✅ 63ms, 0% packet loss

### Azure: Virtual WAN (IPv6 NOT Supported)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Cloud                                   │
│  ┌─────────────────┐              ┌─────────────────┐               │
│  │  Virtual WAN    │              │   Dual-Stack    │               │
│  │     Hub         │──────────────│      VNet       │               │
│  │  10.0.0.0/24    │              │  10.1.0.0/16    │               │
│  └────────┬────────┘              │  2001:db8:1::/48│               │
│           │                       └─────────────────┘               │
│  ┌────────┴────────┐                                                │
│  │   VPN Gateway   │                                                │
│  │   (IPv4 ONLY)   │◄──── ❌ IPv6 NOT SUPPORTED                     │
│  └────────┬────────┘                                                │
│           │                                                          │
│  ┌────────┴────────┐                                                │
│  │    VPN Site     │                                                │
│  │ ❌ Cannot include│                                                │
│  │   IPv6 prefixes │                                                │
│  └─────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────┘
```

**Blocking Issues:**
1. `VpnSiteIpv6NotSupported`: VPN Sites cannot contain IPv6 address prefixes
2. S2S VPN tunnels are IPv4-only
3. BGP peering is IPv4-only

**Conclusion:** Azure Virtual WAN does not support dual-stack S2S VPN connectivity.

---

## Cloud Provider Comparison

| Capability | Azure VWAN | GCP HA VPN | AWS TGW VPN |
|------------|------------|------------|-------------|
| **True dual-stack single tunnel** | ❌ | ❌* | ❌ |
| **IPv6 VPN support** | ❌ | ✅ | ✅ |
| **Configuration approach** | N/A | Dedicated IPv6 BGP | Separate connections |
| **IPv6 BGP sessions** | ❌ | ✅ Required | ✅ Required |
| **Cross-VPN IPv4** | ❌ | ✅ 32ms | ✅ |
| **Cross-VPN IPv6** | ❌ | ✅ 33ms | ✅ 63ms |
| **Deployment time** | 30-45 min | ~3 min | ~5 min |
| **Complexity** | N/A | Medium | High |

*GCP requires dedicated IPv6 BGP sessions; MP-BGP on IPv4 sessions doesn't work.

---

## Directory Structure

```
cloud_provi/
├── README.md                       # This file
├── CLAUDE.md                       # AI assistant instructions
│
├── terraform-gcp/                  # GCP HA VPN (RECOMMENDED)
│   ├── main.tf                     # VPCs, HA VPN, BGP routers
│   ├── README.md                   # GCP-specific instructions
│   └── terraform.tfvars.example
│
├── terraform-aws/                  # AWS Transit Gateway VPN
│   ├── main.tf                     # TGW, VPN connections, VPC
│   ├── outputs.tf                  # Tunnel configurations
│   └── terraform.tfvars.example
│
├── terraform-onprem-sim/           # GCP-hosted on-prem simulation
│   ├── main.tf                     # Router VMs + test VM
│   ├── cloud-init-router.yaml      # FreeSwan + FRR bootstrap
│   ├── configure-aws-ipv6-vpn.sh   # AWS IPv6 tunnel setup script
│   └── outputs.tf
│
├── terraform/                      # Azure Virtual WAN (LIMITED)
│   ├── main.tf                     # VWAN, Hub, VPN Gateway
│   ├── onprem-simulation.tf        # Simulated on-prem
│   └── cloud-init-vpn.yaml         # strongSwan + FRR
│
└── docs/                           # Technical documentation
    ├── gcp-dual-stack-vpn-solution.pdf
    ├── gcp-dual-stack-vpn-solution.typ
    ├── aws-dual-stack-vpn.pdf
    └── aws-dual-stack-vpn.typ
```

---

## Implementation Details

### GCP: Dedicated IPv6 BGP Sessions

The key to making GCP dual-stack work is using dedicated IPv6 BGP sessions instead of relying on MP-BGP:

```hcl
# Reserve ULA range for BGP peering
# fdff:1::/64 - BGP peering addresses
# /126 subnets per tunnel pair

locals {
  bgp_v6_cloud_0  = "fdff:1::1/126"   # Tunnel 0: cloud side
  bgp_v6_onprem_0 = "fdff:1::2/126"   # Tunnel 0: on-prem side
  bgp_v6_cloud_1  = "fdff:1::5/126"   # Tunnel 1: cloud side
  bgp_v6_onprem_1 = "fdff:1::6/126"   # Tunnel 1: on-prem side
}

# Create dedicated IPv6 interface
resource "google_compute_router_interface" "cloud_interface_0_v6" {
  name       = "interface-cloud-0-v6"
  router     = google_compute_router.cloud_router.name
  ip_range   = local.bgp_v6_cloud_0
  vpn_tunnel = google_compute_vpn_tunnel.cloud_to_onprem_0.name
}

# Create IPv6 BGP peer
resource "google_compute_router_peer" "cloud_peer_0_v6" {
  name            = "peer-cloud-to-onprem-0-v6"
  router          = google_compute_router.cloud_router.name
  peer_ip_address = "fdff:1::2"
  peer_asn        = 65002
  interface       = google_compute_router_interface.cloud_interface_0_v6.name
  enable_ipv6     = true
}
```

### AWS: Separate IPv4 and IPv6 VPN Connections

AWS requires completely separate VPN connections for each address family:

```hcl
# IPv4 VPN Connection
resource "aws_vpn_connection" "to_onprem_r1_v4" {
  customer_gateway_id      = aws_customer_gateway.onprem_r1.id
  transit_gateway_id       = aws_ec2_transit_gateway.main.id
  type                     = "ipsec.1"
  tunnel_inside_ip_version = "ipv4"  # Traffic: 0.0.0.0/0
}

# IPv6 VPN Connection (separate!)
resource "aws_vpn_connection" "to_onprem_r1_v6" {
  customer_gateway_id      = aws_customer_gateway.onprem_r1.id
  transit_gateway_id       = aws_ec2_transit_gateway.main.id
  type                     = "ipsec.1"
  tunnel_inside_ip_version = "ipv6"  # Traffic: ::/0
}
```

Router-side IPsec configuration for IPv6 tunnel:
```bash
# /etc/ipsec.d/aws-v6-tunnel.conf
conn aws-v6-tunnel
    leftsubnet=::/0       # IPv6 traffic selector
    rightsubnet=::/0      # IPv6 traffic selector
    # ... other settings
```

---

## Troubleshooting

### GCP: IPv6 Routes Not Being Installed

**Symptom:** BGP shows IPv6 routes advertised but `ping6` fails.

**Cause:** Using `enable_ipv6=true` on IPv4 BGP sessions (MP-BGP) doesn't properly install routes.

**Solution:** Create dedicated IPv6 BGP sessions with IPv6 peering addresses.

### AWS: IPv6 Ping Fails Over VPN

**Symptom:** IPv4 works but IPv6 doesn't traverse the tunnel.

**Cause:** Using IPv4 VPN connection for IPv6 traffic.

**Solution:** Create separate IPv6 VPN connection with `tunnel_inside_ip_version = "ipv6"`.

### Azure: VPN Site Creation Fails

**Error:** `VpnSiteIpv6NotSupported`

**Cause:** Azure Virtual WAN VPN Sites do not support IPv6.

**Solution:** None available. Use GCP or AWS for dual-stack requirements.

### General: NSG/Firewall Rule Errors

**Error:** `ResourceCannotContainAddressPrefixesFromDifferentAddressFamilies`

**Cause:** Mixing IPv4 and IPv6 in the same firewall rule.

**Solution:** Create separate rules for IPv4 and IPv6.

---

## Recommendations

1. **For dual-stack VPN:** Use **GCP HA VPN** - fastest deployment, cleanest architecture
2. **For AWS environments:** Use **Transit Gateway** with separate IPv4/IPv6 connections
3. **For Azure:** Wait for IPv6 VPN support or use alternative connectivity (ExpressRoute, overlay)

---

## Test Results Summary (January 2025)

### GCP HA VPN
```bash
# From cloud VM to on-prem VM
$ ping 192.168.1.2
64 bytes from 192.168.1.2: icmp_seq=1 ttl=62 time=32.1 ms

$ ping6 fd20:b:1:1000::
64 bytes from fd20:b:1:1000::: icmp_seq=1 ttl=62 time=33.4 ms
```

### AWS Transit Gateway VPN
```bash
# From on-prem router to AWS EC2
$ ping6 2600:1f18:50a6:6e01::
64 bytes from 2600:1f18:50a6:6e01::: icmp_seq=1 ttl=62 time=67.7 ms
```

### Azure Virtual WAN
```
❌ IPv6 VPN not supported - no test possible
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes in a non-production environment
4. Submit a pull request

---

## License

MIT License - See LICENSE file for details.
