# Azure Dual-Stack Virtual WAN Infrastructure Specification

## Overview

This specification defines a dual-stack (IPv4 + IPv6) Azure networking infrastructure consisting of:
- Dual-stack Virtual Network (VNet)
- Dual-stack Virtual WAN Hub (vHub)
- Site-to-Site VPN connectivity to on-premises

### Deployment Options

1. **Production Mode**: Connect to real on-premises VPN hardware
2. **Simulation Mode**: Deploy a simulated on-prem environment in Azure using:
   - Separate VNet in a different region
   - Ubuntu VM with strongSwan (IPsec) + FRR (BGP)
   - Test VM for connectivity validation

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Azure Cloud                                  │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                    Virtual WAN                                  │ │
│  │  ┌──────────────────────────────────────────────────────────┐  │ │
│  │  │              Virtual Hub (Dual-Stack)                     │  │ │
│  │  │         IPv4: 10.0.0.0/24 | IPv6: fd00:db8::/64          │  │ │
│  │  │                                                           │  │ │
│  │  │  ┌─────────────┐    ┌─────────────┐    ┌──────────────┐  │  │ │
│  │  │  │ VPN Gateway │    │   Router    │    │  Hub Subnet  │  │  │ │
│  │  │  │ (S2S VPN)   │    │             │    │              │  │  │ │
│  │  │  └──────┬──────┘    └─────────────┘    └──────────────┘  │  │ │
│  │  └─────────┼────────────────────────────────────────────────┘  │ │
│  └────────────┼───────────────────────────────────────────────────┘ │
│               │                                                      │
│               │ VNet Connection                                      │
│               │                                                      │
│  ┌────────────▼───────────────────────────────────────────────────┐ │
│  │              Virtual Network (Dual-Stack)                       │ │
│  │         IPv4: 10.1.0.0/16 | IPv6: 2001:db8:1::/48              │ │
│  │                                                                  │ │
│  │  ┌────────────────────┐    ┌────────────────────┐               │ │
│  │  │   Subnet-1         │    │   Subnet-2         │               │ │
│  │  │ IPv4: 10.1.1.0/24  │    │ IPv4: 10.1.2.0/24  │               │ │
│  │  │ IPv6: 2001:db8:1:  │    │ IPv6: 2001:db8:1:  │               │ │
│  │  │       1::/64       │    │       2::/64       │               │ │
│  │  └────────────────────┘    └────────────────────┘               │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                    │
                    │ IPsec/IKEv2 Tunnel (Dual-Stack)
                    │
┌───────────────────▼─────────────────────────────────────────────────┐
│                       On-Premises Network                            │
│                IPv4: 192.168.0.0/16 | IPv6: 2001:db8:2::/48         │
│                                                                      │
│  ┌─────────────────┐                                                 │
│  │   VPN Device    │                                                 │
│  │ (IKEv2 capable) │                                                 │
│  └─────────────────┘                                                 │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Component Specifications

### 1. Resource Group

| Property | Value |
|----------|-------|
| Name | `rg-dualstack-vwan-<env>-<region>` |
| Location | `<primary-region>` (e.g., eastus2) |
| Tags | See [Tagging Strategy](#tagging-strategy) |

### 2. Virtual WAN

| Property | Value |
|----------|-------|
| Name | `vwan-dualstack-<env>-<region>` |
| Type | Standard |
| Allow Branch-to-Branch | true |
| Office365 Local Breakout | Enabled (optional) |

### 3. Virtual Hub (Dual-Stack)

| Property | Value |
|----------|-------|
| Name | `vhub-dualstack-<env>-<region>` |
| Region | `<primary-region>` |
| IPv4 Address Prefix | `10.0.0.0/24` |
| IPv6 Address Prefix | `fd00:db8::/64` |
| Hub Routing Preference | ExpressRoute > VPN > AS Path |
| Virtual Router ASN | 65515 (default) |
| Capacity | 2 Routing Infrastructure Units (min) |

#### Hub Features to Enable
- [x] VPN Gateway (Site-to-Site)
- [ ] ExpressRoute Gateway (if needed)
- [ ] Point-to-Site Gateway (if needed)
- [ ] Azure Firewall (if needed)

### 4. Virtual Network (Dual-Stack)

| Property | Value |
|----------|-------|
| Name | `vnet-workload-<env>-<region>` |
| IPv4 Address Space | `10.1.0.0/16` |
| IPv6 Address Space | `2001:db8:1::/48` (or ULA range) |
| DNS Servers | Azure-provided or custom |
| DDoS Protection | Standard (recommended for production) |

#### Subnets

| Subnet Name | IPv4 CIDR | IPv6 CIDR | Purpose |
|-------------|-----------|-----------|---------|
| `snet-workload-01` | `10.1.1.0/24` | `2001:db8:1:1::/64` | Application workloads |
| `snet-workload-02` | `10.1.2.0/24` | `2001:db8:1:2::/64` | Database tier |
| `snet-mgmt` | `10.1.3.0/24` | `2001:db8:1:3::/64` | Management/bastion |
| `AzureBastionSubnet` | `10.1.255.0/26` | N/A | Azure Bastion (IPv4 only) |

### 5. VPN Gateway (in vHub)

| Property | Value |
|----------|-------|
| Name | `vpngw-dualstack-<env>-<region>` |
| Gateway Scale Units | 1 (500 Mbps) - adjust as needed |
| Routing Preference | Microsoft Network |
| BGP Enabled | true |
| BGP ASN | 65515 (Azure default) |

### 6. VPN Site (On-Premises)

| Property | Value |
|----------|-------|
| Name | `vpnsite-onprem-<location>` |
| Device Vendor | `<vendor>` |
| Device Model | `<model>` |
| Link Speed | `<speed-mbps>` |
| IPv4 Address | `<public-ip-of-vpn-device>` |
| IPv6 Address | `<ipv6-if-available>` |
| BGP Enabled | true |
| BGP Peer IPv4 | `<on-prem-bgp-peer-ip>` |
| BGP Peer IPv6 | `<on-prem-bgp-peer-ipv6>` |
| BGP ASN | `<on-prem-asn>` (e.g., 65001) |

#### Address Spaces to Advertise

| Type | CIDR |
|------|------|
| On-Prem IPv4 | `192.168.0.0/16` |
| On-Prem IPv6 | `2001:db8:2::/48` |

### 7. VPN Connection

| Property | Value |
|----------|-------|
| Name | `conn-onprem-<location>` |
| Connection Protocol | IKEv2 |
| IPsec Policy | Custom (see below) |
| Enable BGP | true |
| Use Policy-Based Traffic Selector | false |
| Routing Weight | 0 |

#### IPsec/IKE Policy (Recommended)

| Phase | Parameter | Value |
|-------|-----------|-------|
| IKE Phase 1 | Encryption | AES256 |
| | Integrity | SHA256 |
| | DH Group | DHGroup14 or DHGroup24 |
| | SA Lifetime | 28800 seconds |
| IKE Phase 2 | Encryption | GCMAES256 |
| | Integrity | GCMAES256 |
| | PFS Group | PFS2048 or PFS24 |
| | SA Lifetime | 27000 seconds |

### 8. Simulated On-Premises Environment (Optional)

For testing without real hardware, deploy a simulated on-prem environment:

| Component | Specification |
|-----------|--------------|
| **Resource Group** | `rg-onprem-sim-<env>-<region>` |
| **Location** | Different region (e.g., westus2) |
| **VNet IPv4** | `192.168.0.0/16` |
| **VNet IPv6** | `2001:db8:2::/48` |

#### VPN Gateway VM

| Property | Value |
|----------|-------|
| Name | `vm-vpn-onprem-sim-<env>` |
| Size | `Standard_B2s` (min) |
| OS | Ubuntu 22.04 LTS |
| Software | strongSwan (IPsec) + FRR (BGP) |
| Public IP | Static, Standard SKU |
| IP Forwarding | Enabled |

#### strongSwan Configuration

- **IKE Version**: IKEv2
- **Phase 1**: AES256-SHA256-MODP2048
- **Phase 2**: AES256GCM16-MODP2048
- **DPD**: 30s interval, restart action

#### FRR/BGP Configuration

| Property | Value |
|----------|-------|
| BGP ASN | 65001 |
| Router ID | 192.168.0.4 |
| Neighbors | Azure VPN Gateway instances |
| Networks | `192.168.0.0/16`, `2001:db8:2::/48` |

#### Test VM

| Property | Value |
|----------|-------|
| Name | `vm-test-onprem-sim-<env>` |
| Size | `Standard_B1s` |
| Subnet | `snet-workload` (192.168.1.0/24) |
| Purpose | Connectivity testing |

---

## IPv6 Considerations

### Current Limitations (as of Jan 2025)

1. **Virtual WAN IPv6 Support**: Generally Available but verify feature flags
2. **VPN Gateway IPv6**: Supported for S2S VPN
3. **Azure Bastion**: IPv4 only - cannot use IPv6 for bastion connections
4. **Network Security Groups**: Full IPv6 support
5. **Azure Firewall**: IPv6 support available in Standard and Premium SKUs
6. **Load Balancer**: Standard SKU supports dual-stack

### Best Practices

- Use ULA (Unique Local Address) ranges for private IPv6 if not using public IPv6
- Ensure on-premises VPN device supports IPv6 over IPsec
- Configure both IPv4 and IPv6 routes for BGP peering
- Test IPv6 connectivity thoroughly before production

---

## Tagging Strategy

| Tag Name | Example Value | Purpose |
|----------|---------------|---------|
| `Environment` | `dev`, `staging`, `prod` | Identify environment |
| `Project` | `dual-stack-vwan` | Project name |
| `Owner` | `network-team@company.com` | Responsible team |
| `CostCenter` | `IT-12345` | Cost allocation |
| `CreatedBy` | `terraform` | Deployment method |
| `CreatedDate` | `2025-01-14` | Creation date |

---

## Security Requirements

### Network Security Groups (NSGs)

Create NSGs with rules for:
- Allow inbound ICMP (for connectivity testing)
- Allow inbound from on-premises ranges
- Deny all other inbound (default)
- Allow all outbound (or restrict as needed)

### Encryption

- All VPN traffic encrypted with IPsec
- Use custom IPsec policies (not Azure defaults)
- Consider Azure Private Link for PaaS services

### Monitoring

- Enable Azure Network Watcher
- Configure VPN diagnostics logs
- Set up Azure Monitor alerts for:
  - VPN tunnel disconnection
  - BGP peer state changes
  - High latency thresholds

---

## Deployment Order

1. Resource Group
2. Virtual WAN
3. Virtual Hub
4. VPN Gateway (in Hub)
5. Virtual Network (Dual-Stack)
6. VNet-to-Hub Connection
7. VPN Site
8. VPN Connection
9. Configure on-premises VPN device
10. Verify BGP peering and routes
11. Test connectivity (IPv4 and IPv6)

---

## Estimated Costs (Monthly)

| Resource | SKU/Size | Estimated Cost |
|----------|----------|----------------|
| Virtual WAN | Standard | ~$0.05/hr |
| Virtual Hub | Base | ~$0.25/hr |
| VPN Gateway | 1 Scale Unit | ~$0.361/hr |
| S2S VPN Connection | Per connection | ~$0.015/hr |
| Data Transfer | Per GB | Variable |

**Note**: Verify current pricing at [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)

---

## References

- [Azure Virtual WAN Documentation](https://learn.microsoft.com/azure/virtual-wan/)
- [IPv6 for Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/ip-services/ipv6-overview)
- [Virtual WAN S2S VPN](https://learn.microsoft.com/azure/virtual-wan/virtual-wan-site-to-site-portal)
- [BGP with Virtual WAN](https://learn.microsoft.com/azure/virtual-wan/virtual-wan-site-to-site-portal#configure-bgp)
