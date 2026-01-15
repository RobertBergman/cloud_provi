#set document(
  title: "Azure VPN Gateway Dual-Stack Analysis",
  author: "Cloud Infrastructure Team",
  date: datetime.today(),
)

#set page(
  paper: "us-letter",
  margin: (x: 1in, y: 1in),
  header: align(right)[_Azure VPN Gateway Dual-Stack Analysis_],
  footer: context align(center)[#counter(page).display("1 of 1", both: true)],
)

#set text(font: "New Computer Modern", size: 11pt)
#set heading(numbering: "1.1")
#set par(justify: true)

#align(center)[
  #text(size: 24pt, weight: "bold")[Azure VPN Gateway Dual-Stack Analysis]

  #v(0.5em)
  #text(size: 14pt)[Cross-Premises IPv6 Connectivity Assessment]

  #v(1em)
  #text(size: 12pt)[January 2026]
]

#v(2em)

#outline(title: "Contents", indent: auto)

#pagebreak()

= Executive Summary

This report documents the analysis of Azure VPN Gateway's dual-stack (IPv4 + IPv6) capabilities for cross-premises connectivity. Testing was conducted using a GCP-hosted on-premises simulation connecting to Azure VPN Gateway in Active-Active mode.

#block(fill: rgb("#fff3cd"), inset: 10pt, radius: 4pt)[
  *Key Finding*: Azure VPN Gateway dual-stack IPv6 is available in *PREVIEW* status, requiring explicit opt-in by emailing your subscription ID to Microsoft. Without preview enrollment, IPv6 is blocked at multiple levels.
]

#block(fill: rgb("#d1ecf1"), inset: 10pt, radius: 4pt)[
  *Preview Availability*: Microsoft documents dual-stack Site-to-Site VPN support with:
  - Manual opt-in required (email subscription ID to Microsoft)
  - Supported SKUs: VpnGw1-5, VpnGw1AZ-5AZ
  - IKEv2 required (IKEv1 does not support IPv6)
  - New gateway deployments only
]

#v(1em)

*Test Results Summary:*

#table(
  columns: (1fr, auto, auto),
  align: (left, center, center),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Component*], [*IPv4*], [*IPv6*],
  [IPsec Tunnels (IKEv2)], [#text(fill: rgb("#28a745"))[Pass]], [N/A],
  [BGP Sessions], [#text(fill: rgb("#28a745"))[Pass]], [#text(fill: rgb("#dc3545"))[Fail]],
  [Route Learning], [#text(fill: rgb("#28a745"))[Pass]], [#text(fill: rgb("#dc3545"))[Fail]],
  [Cross-VPN Ping], [#text(fill: rgb("#28a745"))[69ms]], [#text(fill: rgb("#dc3545"))[Blocked]],
  [Static Routes (UDR)], [#text(fill: rgb("#28a745"))[Pass]], [#text(fill: rgb("#dc3545"))[Rejected]],
)

= Test Environment

== Architecture

The test environment consisted of:

- *Azure VPN Gateway*: VpnGw1 SKU, Active-Active mode, BGP enabled (ASN 65515)
- *On-Prem Simulation*: Two router VMs on GCP running LibreSwan + FRR
- *Test VMs*: One in Azure, one in GCP on-prem simulation

#figure(
  ```
  ┌─────────────────────────────────────────────────────────────┐
  │                    GCP On-Prem Simulation                   │
  │                        (us-west1)                           │
  │                                                             │
  │  ┌─────────────────┐            ┌─────────────────┐        │
  │  │   Router 1      │            │   Router 2      │        │
  │  │  34.82.67.66    │            │  34.169.9.91    │        │
  │  │  ASN: 65001     │            │  ASN: 65001     │        │
  │  │  BGP: 169.254.  │            │  BGP: 169.254.  │        │
  │  │       21.5      │            │       21.6      │        │
  │  └────────┬────────┘            └────────┬────────┘        │
  │           │                              │                  │
  │           │   VPC: 192.168.0.0/16        │                  │
  │           │         fd20:e:1::/48        │                  │
  │           └──────────────┬───────────────┘                  │
  │                          │                                  │
  │               ┌──────────┴──────────┐                       │
  │               │   Test VM           │                       │
  │               │   192.168.1.100     │                       │
  │               └─────────────────────┘                       │
  └─────────────────────────────────────────────────────────────┘
                │                              │
                │ IPsec IKEv2                  │ IPsec IKEv2
                │ vti10                        │ vti10
                ▼                              ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                    Azure (eastus2)                          │
  │                                                             │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │              Azure VPN Gateway                       │   │
  │  │              (Active-Active, VpnGw1)                 │   │
  │  │                                                      │   │
  │  │  Instance 0: 20.110.156.183  │  Instance 1: 172.177. │   │
  │  │  BGP: 169.254.21.1           │  98.104               │   │
  │  │  ASN: 65515                  │  BGP: 169.254.21.2    │   │
  │  └──────────────────────────────────────────────────────┘   │
  │                          │                                  │
  │           VNet: 10.1.0.0/16 + fd20:d:1::/48                │
  │                          │                                  │
  │               ┌──────────┴──────────┐                       │
  │               │   Test VM           │                       │
  │               │   10.1.1.100        │                       │
  │               │   fd20:d:1:1::4     │                       │
  │               └─────────────────────┘                       │
  └─────────────────────────────────────────────────────────────┘
  ```,
  caption: [Test Environment Architecture]
)

== IP Addressing

#table(
  columns: (1fr, 1fr, 1fr),
  align: (left, left, left),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Component*], [*IPv4*], [*IPv6*],
  [Azure VNet], [`10.1.0.0/16`], [`fd20:d:1::/48`],
  [Azure GatewaySubnet], [`10.1.0.0/27`], [N/A (not supported)],
  [Azure Workload Subnet], [`10.1.1.0/24`], [`fd20:d:1:1::/64`],
  [Azure Test VM], [`10.1.1.100`], [`fd20:d:1:1::4`],
  [On-Prem VPC], [`192.168.0.0/16`], [`fd20:e:1::/48`],
  [On-Prem Router 1], [`192.168.0.10`], [auto-assigned],
  [On-Prem Router 2], [`192.168.0.11`], [auto-assigned],
  [On-Prem Test VM], [`192.168.1.100`], [auto-assigned],
)

== BGP Configuration

#table(
  columns: (1fr, 1fr, 1fr),
  align: (left, center, left),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Side*], [*ASN*], [*BGP Peering IPs (APIPA)*],
  [Azure VPN Gateway Instance 0], [65515], [`169.254.21.1`],
  [Azure VPN Gateway Instance 1], [65515], [`169.254.21.2`],
  [On-Prem Router 1], [65001], [`169.254.21.5`],
  [On-Prem Router 2], [65001], [`169.254.21.6`],
)

= IPv4 VPN Results

IPv4 connectivity was successfully established through the Azure VPN Gateway.

== IPsec Tunnel Status

Both IPsec tunnels established successfully using IKEv2:

```
#1: "azure-vpngw-tun1":4500 STATE_PARENT_I3 (PARENT SA established)
#2: "azure-vpngw-tun1":4500 STATE_V2_IPSEC_I (IPsec SA established)
```

*IPsec Parameters:*
- IKE: AES256-SHA256-MODP2048
- ESP: AES256-SHA256
- IKE Lifetime: 28800s
- SA Lifetime: 3600s

== BGP Session Status

Both BGP sessions established and exchanging routes:

```
Neighbor        V    AS   MsgRcvd MsgSent  Up/Down  State/PfxRcd
169.254.21.1    4 65515        3       5 00:00:41            1
169.254.21.2    4 65515        3       5 00:00:16            1
```

== Connectivity Test Results

#table(
  columns: (1fr, auto, auto),
  align: (left, center, center),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Test*], [*Result*], [*Latency*],
  [On-Prem → Azure (ping 10.1.1.100)], [#text(fill: rgb("#28a745"))[0% loss]], [69ms],
  [Azure → On-Prem (ping 192.168.1.100)], [#text(fill: rgb("#28a745"))[0% loss]], [69ms],
  [BGP Route Learning (10.1.0.0/16)], [#text(fill: rgb("#28a745"))[Learned]], [--],
)

= IPv6 VPN Results

#block(fill: rgb("#f8d7da"), inset: 10pt, radius: 4pt)[
  *Critical Finding*: Azure VPN Gateway does not support cross-premises IPv6 connectivity at any level.
]

== Blocking Issue 1: Local Network Gateway Rejects IPv6

When attempting to add IPv6 prefixes to the Local Network Gateway:

```bash
az network local-gateway update \
  --name lng-onprem-router-1-prod-eastus2 \
  --local-address-prefixes 192.168.0.0/16 fd20:e:1::/48
```

*Error Response:*
```
LocalNetworkGatewayIpv6NotSupported: Local Network Gateway
cannot contain IPv6 address prefix.
```

This is a fundamental limitation. The Local Network Gateway, which defines on-premises address spaces, explicitly rejects IPv6 prefixes.

== Blocking Issue 2: BGP Does Not Learn IPv6 Routes

Although the BGP neighbor capability shows IPv6 Unicast support:

```
Address Family IPv6 Unicast: received
```

Azure VPN Gateway does *not* install IPv6 routes in its routing table. When on-prem routers advertise `fd20:e:1::/48`:

```bash
az network vnet-gateway list-learned-routes \
  --name vpngw-azure-prod-eastus2 \
  --resource-group rg-azure-vpngw-prod-eastus2
```

*Result:* Only IPv4 routes appear. No IPv6 routes are learned.

== Blocking Issue 3: UDR Cannot Route IPv6 to VPN Gateway

Attempting to create a static route for IPv6 to the VPN Gateway:

```bash
az network route-table route create \
  --address-prefix fd20:e:1::/48 \
  --next-hop-type VirtualNetworkGateway
```

*Error Response:*
```
InvalidNextHopType: The next hop type for IPv6 address prefix
fd20:e:1::/48 cannot be 'VirtualNetworkGateway',
'HyperNetGateway' or 'VirtualNetworkServiceEndpoint'.
```

Azure explicitly blocks IPv6 routes from using VPN Gateway as a next hop.

== Blocking Issue 4: Overlay Tunnels Blocked

As a workaround, we attempted to create a GRE tunnel (IPv6-in-IPv4) over the working VPN:

#table(
  columns: (1fr, 1fr),
  align: (left, left),
  stroke: 0.5pt,
  inset: 8pt,
  [*Azure VM Side*], [*On-Prem Router Side*],
  [GRE tunnel to 192.168.0.10], [GRE tunnel to 10.1.1.100],
  [IPv6 address: fd20:ff::1/126], [IPv6 address: fd20:ff::2/126],
)

*Result:* GRE packets (IP protocol 47) are filtered by Azure networking. tcpdump on the on-prem router shows zero GRE packets arriving, despite Azure VM sending them.

```
# Azure VM tcpdump shows outgoing GRE:
IP 10.1.1.100 > 192.168.0.10: GREv0, length 108: IP6 ...

# On-prem router tcpdump shows nothing:
0 packets captured
```

ICMP and TCP to the same destination work fine, confirming the VPN tunnel is functional but GRE is specifically filtered.

= Comparison with Other Cloud Providers

#table(
  columns: (1fr, auto, auto, auto, auto),
  align: (left, center, center, center, center),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Capability*], [*Azure VWAN*], [*Azure VPN GW*], [*GCP HA VPN*], [*AWS TGW VPN*],
  [IPv4 VPN], [#text(fill: rgb("#28a745"))[GA]], [#text(fill: rgb("#28a745"))[GA]], [#text(fill: rgb("#28a745"))[GA]], [#text(fill: rgb("#28a745"))[GA]],
  [IPv6 VPN Config], [#text(fill: rgb("#dc3545"))[No]], [#text(fill: rgb("#fd7e14"))[Preview†]], [#text(fill: rgb("#28a745"))[GA]], [#text(fill: rgb("#28a745"))[GA]],
  [IPv6 in LNG/Site], [#text(fill: rgb("#dc3545"))[Rejected]], [#text(fill: rgb("#fd7e14"))[Preview†]], [N/A], [N/A],
  [IPv6 BGP Sessions], [#text(fill: rgb("#dc3545"))[No]], [#text(fill: rgb("#fd7e14"))[Preview†]], [#text(fill: rgb("#28a745"))[GA]], [#text(fill: rgb("#28a745"))[GA]],
  [IPv6 Route Learning], [#text(fill: rgb("#dc3545"))[No]], [#text(fill: rgb("#fd7e14"))[Preview†]], [#text(fill: rgb("#28a745"))[GA‡]], [#text(fill: rgb("#28a745"))[GA]],
  [IPv6 UDR to Gateway], [#text(fill: rgb("#dc3545"))[Blocked]], [#text(fill: rgb("#fd7e14"))[Preview†]], [N/A], [N/A],
  [Cross-VPN IPv4], [69ms], [69ms], [32ms], [63ms],
  [Cross-VPN IPv6], [#text(fill: rgb("#dc3545"))[Blocked]], [#text(fill: rgb("#fd7e14"))[Untested]], [33ms], [63ms],
  [Deployment Time], [30-45 min], [30-45 min], [\~3 min], [\~5 min],
  [Feature Status], [GA], [GA + Preview], [GA], [GA],
)

#text(size: 9pt)[† Azure VPN Gateway IPv6 requires manual preview enrollment (email subscription ID to Microsoft)]

#text(size: 9pt)[‡ GCP requires dedicated IPv6 BGP sessions rather than MP-BGP on IPv4 sessions]

== AWS Approach (Works)

AWS supports dual-stack by creating *separate VPN connections*:
- One VPN connection with `tunnel_inside_ip_version = "ipv4"` (traffic selector: `0.0.0.0/0`)
- One VPN connection with `tunnel_inside_ip_version = "ipv6"` (traffic selector: `::/0`)

This approach is *not possible with Azure* because the Local Network Gateway rejects IPv6 entirely.

== GCP Approach (Works)

GCP supports dual-stack with:
- HA VPN Gateway with `stack_type = "IPV4_IPV6"`
- Dedicated IPv6 BGP sessions using `fdff:1::/64` peering addresses
- IPv6 routes properly installed in VPC routing table

= Technical Details

== IPsec Configuration (LibreSwan)

The following LibreSwan configuration successfully establishes IPv4 tunnels:

```bash
conn azure-vpngw-tun1
    authby=secret
    auto=start
    left=%defaultroute
    leftid=34.82.67.66
    right=20.110.156.183
    type=tunnel
    ikev2=yes
    ikelifetime=28800s
    salifetime=3600s
    ike=aes256-sha256-modp2048
    esp=aes256-sha256
    keyingtries=%forever
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=300/0xffffffff
    vti-interface=vti10
    vti-routing=no
    dpddelay=10
    dpdtimeout=30
    dpdaction=restart_by_peer
```

*Important LibreSwan Syntax Notes:*
- Use `ikev2=yes` (not `keyexchange=ikev2`)
- Use `ikelifetime=` (not `ikesalifetime=`)
- Use `salifetime=` (not `lifetime=`)

== VTI Route Requirement

Azure BGP uses APIPA addresses (169.254.x.x). A static route must be added to ensure BGP traffic traverses the VTI interface:

```bash
ip route add 169.254.21.1/32 dev vti10
```

Without this route, BGP traffic exits the wrong interface and sessions fail to establish.

= Enterprise Architecture: ExpressRoute + VPN Dual-Stack

For production environments, Microsoft recommends ExpressRoute as primary with S2S VPN as backup, both configured for dual-stack.

== Target Architecture

#figure(
  ```
  ┌─────────────────────────────────────────────────────────────┐
  │                    On-Premises (Dual-Stack)                 │
  │                                                             │
  │  ┌─────────────────┐            ┌─────────────────┐        │
  │  │  ER Edge Router │            │  VPN Edge Router│        │
  │  │  (BGP IPv4+v6)  │            │  (IKEv2, BGP)   │        │
  │  └────────┬────────┘            └────────┬────────┘        │
  └───────────┼──────────────────────────────┼─────────────────┘
              │                              │
              │ ExpressRoute                 │ S2S VPN
              │ (PRIMARY)                    │ (BACKUP)
              │ Private Peering              │ Over Internet
              │ IPv4 + IPv6                  │ IPv4 outer, dual-stack inner
              ▼                              ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                    Azure Hub VNet (Dual-Stack)              │
  │                                                             │
  │  ┌─────────────────────────────────────────────────────┐   │
  │  │              GatewaySubnet (/27 or larger)           │   │
  │  │                                                      │   │
  │  │  ┌─────────────────┐    ┌─────────────────┐         │   │
  │  │  │  ExpressRoute   │    │  VPN Gateway    │         │   │
  │  │  │  Gateway        │    │  (Dual-Stack)   │         │   │
  │  │  │                 │    │  VpnGw1-5/AZ    │         │   │
  │  │  └─────────────────┘    └─────────────────┘         │   │
  │  └──────────────────────────────────────────────────────┘   │
  │                          │                                  │
  │           VNet: IPv4 + IPv6 (Global Unicast)               │
  │                          │                                  │
  │               ┌──────────┴──────────┐                       │
  │               │   Spoke VNets       │                       │
  │               │   (Peered)          │                       │
  │               └─────────────────────┘                       │
  └─────────────────────────────────────────────────────────────┘
  ```,
  caption: [Enterprise Dual-Stack Architecture: ExpressRoute Primary + VPN Backup]
)

== ExpressRoute Dual-Stack (Primary Path)

*Configuration Requirements:*

#table(
  columns: (1fr, 2fr),
  align: (left, left),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Component*], [*Requirement*],
  [Private Peering IPv6], [Add /126 IPv6 subnets (primary + secondary)],
  [Prefix Limits], [4000 IPv4 prefixes, 100 IPv6 prefixes to Microsoft],
  [Circuit Support], [Must enable dual-stack on circuit before gateway attachment],
  [Gateway], [ER gateway in dual-stack VNet],
)

#block(fill: rgb("#fff3cd"), inset: 10pt, radius: 4pt)[
  *Design Tip*: Summarize IPv6 aggressively to stay under the 100-prefix ceiling.
]

== S2S VPN Dual-Stack (Backup Path)

*Preview Constraints:*

- Preview enrollment required (new deployments only)
- Cannot convert existing IPv4-only gateway to dual-stack
- Supported SKUs: VpnGw1-5 / VpnGw1AZ-5AZ
- IKEv2 required (IKEv1 does not support IPv6)
- Dual-stack gateways cannot be reverted to IPv4-only

== Routing & Failover Behavior

*Azure Side:*
- If same prefixes advertised over both ER and VPN, Azure prefers ExpressRoute
- Longest prefix match still applies first
- Advertise identical summarized prefixes over both paths

*On-Prem Side:*
- Set BGP Local Preference to favor ER-learned routes
- Optionally AS-path prepend on VPN BGP advertisements
- Prevents asymmetric routing during partial failures

#block(fill: rgb("#d1ecf1"), inset: 10pt, radius: 4pt)[
  *Failover Behavior*: When ER fails, traffic automatically shifts to VPN. When ER recovers, traffic returns to ER (preferred path).
]

== Critical Limitations

#block(fill: rgb("#f8d7da"), inset: 10pt, radius: 4pt)[
  *Azure Route Server*: Does NOT support IPv6. Placing Route Server in a VNet with IPv6 can break IPv6 connectivity. Keep Route Server hub IPv4-only if needed for NVA BGP.
]

#block(fill: rgb("#f8d7da"), inset: 10pt, radius: 4pt)[
  *Azure Firewall*: Does NOT support IPv6 filtering. Can exist in dual-stack VNet but firewall subnet must be IPv4-only.
]

== Implementation Checklist

#table(
  columns: (auto, 1fr, auto),
  align: (center, left, center),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Step*], [*Task*], [*Status*],
  [1], [Define IPv4 + IPv6 address plan (summarize!)], [☐],
  [2], [Create Hub VNet dual-stack + GatewaySubnet /27+], [☐],
  [3], [Deploy ExpressRoute gateway (hub)], [☐],
  [4], [Configure ER private peering IPv4 + IPv6 (/126 pairs)], [☐],
  [5], [Deploy VPN gateway dual-stack (new deployment, right SKU, IKEv2)], [☐],
  [6], [Establish on-prem routing policy: prefer ER, VPN backup], [☐],
  [7], [Validate: simulate ER failure → traffic flips to VPN], [☐],
  [8], [Validate: restore ER → traffic returns to ER], [☐],
)

= Conclusions

== Primary Finding

*Azure VPN Gateway dual-stack IPv6 requires explicit preview enrollment.* Without opt-in, IPv6 is blocked at multiple levels:

1. *Local Network Gateway*: Explicitly rejects IPv6 address prefixes
2. *BGP*: Does not learn or install IPv6 routes
3. *User Defined Routes*: Cannot specify VPN Gateway as next-hop for IPv6
4. *Network Filtering*: Blocks overlay protocols (GRE) that could tunnel IPv6

== Azure Dual-Stack VPN Preview

Microsoft documents Site-to-Site VPN dual-stack support in *PREVIEW* status:

#block(fill: rgb("#e7f3ff"), inset: 10pt, radius: 4pt)[
  *How to Enable Preview:*
  1. Email your Azure subscription ID to Microsoft (per documentation)
  2. Deploy a *new* VPN Gateway (cannot upgrade existing)
  3. Use supported SKU: VpnGw1-5 or VpnGw1AZ-5AZ
  4. Configure IKEv2 (IKEv1 does not support IPv6)
]

*Preview Constraints:*
- Manual enrollment process (not self-service)
- New gateway deployments only
- Preview features may change or have limitations
- Production workloads should evaluate risk

== Decision Guide

#table(
  columns: (1fr, 1fr, 1fr),
  align: (left, left, left),
  stroke: 0.5pt,
  inset: 8pt,
  fill: (col, row) => if row == 0 { rgb("#e9ecef") },
  [*Scenario*], [*Recommended Solution*], [*Notes*],
  [Enterprise datacenter extension], [ExpressRoute dual-stack], [Primary path, VPN as backup],
  [Dynamic routing to NVAs], [Plan carefully], [Azure Route Server lacks IPv6 support],
  [Need dual-stack now, no ExpressRoute], [VPN dual-stack preview], [Accept preview constraints],
  [Production with GA features only], [GCP or AWS], [Both have GA dual-stack VPN],
)

== Recommendations

For organizations requiring cross-premises IPv6 connectivity:

1. *Azure with Preview Enrollment*: Request dual-stack preview access
   - Email subscription ID to Microsoft
   - Plan for new gateway deployment
   - Use IKEv2 with supported SKU

2. *Use GCP or AWS*: Both have GA (non-preview) dual-stack VPN
   - GCP: Use dedicated IPv6 BGP sessions
   - AWS: Use separate IPv4 and IPv6 VPN connections

3. *Azure ExpressRoute*: Supports dual-stack (separate consideration)
   - Higher bandwidth than VPN
   - Different deployment model

4. *Avoid Workarounds*: Without preview enrollment:
   - Overlay tunnels (GRE) are filtered
   - UDRs cannot route IPv6 to VPN Gateway
   - BGP will not learn IPv6 routes

== Infrastructure Resources

The following Terraform resources were created for this test:

```
terraform-azure-vpngw/
├── main.tf                     # VNet, subnets, NSG
├── vpn-gateway.tf              # VPN Gateway (Active-Active)
├── local-network-gateways.tf   # On-prem router definitions
├── connections.tf              # IPsec connections
├── test-vm.tf                  # Test VM
├── variables.tf
└── outputs.tf

terraform-onprem-sim/scripts/
└── configure-azure-vpn.sh      # Azure VPN tunnel config script
```

== Useful Commands

*Azure Status Checks:*
```bash
# Connection status
az network vpn-connection show \
  --name conn-to-onprem-router-1-prod-eastus2 \
  --resource-group rg-azure-vpngw-prod-eastus2 \
  --query connectionStatus

# Learned routes
az network vnet-gateway list-learned-routes \
  --name vpngw-azure-prod-eastus2 \
  --resource-group rg-azure-vpngw-prod-eastus2
```

*On-Prem Router Checks:*
```bash
# IPsec status
sudo ipsec status

# BGP status
sudo vtysh -c "show bgp summary"
sudo vtysh -c "show bgp ipv4 unicast"
```

#pagebreak()

= Appendix: Error Messages

== LocalNetworkGatewayIpv6NotSupported

```json
{
  "code": "LocalNetworkGatewayIpv6NotSupported",
  "message": "Local Network Gateway cannot contain IPv6 address prefix."
}
```

== InvalidNextHopType for IPv6

```json
{
  "code": "InvalidNextHopType",
  "message": "The next hop type for IPv6 address prefix fd20:e:1::/48
              cannot be 'VirtualNetworkGateway', 'HyperNetGateway'
              or 'VirtualNetworkServiceEndpoint'."
}
```

== VpnSiteIpv6NotSupported (VWAN)

```json
{
  "code": "VpnSiteIpv6NotSupported",
  "message": "Vpn Site cannot contain IPv6 address prefix."
}
```
