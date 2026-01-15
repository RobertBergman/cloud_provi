# Azure Dual-Stack vWAN Implementation Checklist

## Status Legend
- [ ] Not Started
- [x] Completed
- [~] In Progress
- [!] Blocked

---

## Pre-Implementation

### Prerequisites Verification

- [ ] Azure subscription with appropriate permissions (Contributor/Owner)
- [ ] Verify region supports Virtual WAN with IPv6
- [ ] On-premises VPN device details gathered:
  - [ ] Device vendor and model
  - [ ] Public IP address
  - [ ] BGP ASN
  - [ ] BGP peer IP addresses (IPv4 and IPv6)
  - [ ] Pre-shared key generated
- [ ] IPv4 address ranges defined (Azure and on-prem)
- [ ] IPv6 address ranges defined (Azure and on-prem)
- [ ] Network team approval obtained
- [ ] Cost estimate approved

### Tools Setup

- [ ] Azure CLI installed and logged in
- [ ] Terraform installed (if using IaC)
- [ ] Azure PowerShell modules installed (optional)

---

## Phase 1: Foundation

### 1.1 Resource Group

```bash
# Create resource group
az group create \
  --name rg-dualstack-vwan-prod-eastus2 \
  --location eastus2 \
  --tags Environment=prod Project=dual-stack-vwan Owner=network-team
```

- [ ] Resource group created
- [ ] Tags applied
- [ ] Verified in Azure Portal

### 1.2 Virtual WAN

```bash
# Create Virtual WAN
az network vwan create \
  --name vwan-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --type Standard \
  --branch-to-branch-traffic true
```

- [ ] Virtual WAN created
- [ ] Type = Standard confirmed
- [ ] Branch-to-branch enabled

---

## Phase 2: Virtual Hub (Dual-Stack)

### 2.1 Create Virtual Hub

```bash
# Create Virtual Hub
az network vhub create \
  --name vhub-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --vwan vwan-dualstack-prod-eastus2 \
  --address-prefix 10.0.0.0/24 \
  --location eastus2 \
  --sku Standard
```

- [ ] Virtual Hub created
- [ ] IPv4 prefix configured: `10.0.0.0/24`
- [ ] Hub provisioning completed (can take 10-30 min)

### 2.2 Enable IPv6 on Virtual Hub

```bash
# Add IPv6 prefix to hub (may require portal or ARM template)
# Check current CLI support for IPv6 on vHub
az network vhub update \
  --name vhub-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --address-prefix 10.0.0.0/24 fd00:db8::/64
```

- [ ] IPv6 prefix added: `fd00:db8::/64`
- [ ] Dual-stack status verified

### 2.3 Create VPN Gateway in Hub

```bash
# Create VPN Gateway
az network vpn-gateway create \
  --name vpngw-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --vhub vhub-dualstack-prod-eastus2 \
  --scale-unit 1 \
  --no-wait
```

- [ ] VPN Gateway creation initiated
- [ ] VPN Gateway provisioned (can take 30-45 min)
- [ ] Gateway public IPs noted:
  - [ ] Instance 0: ____________
  - [ ] Instance 1: ____________

---

## Phase 3: Virtual Network (Dual-Stack)

### 3.1 Create Virtual Network

```bash
# Create VNet with dual-stack
az network vnet create \
  --name vnet-workload-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --location eastus2 \
  --address-prefixes 10.1.0.0/16 2001:db8:1::/48
```

- [ ] VNet created
- [ ] IPv4 address space: `10.1.0.0/16`
- [ ] IPv6 address space: `2001:db8:1::/48`

### 3.2 Create Subnets

```bash
# Workload Subnet 1
az network vnet subnet create \
  --name snet-workload-01 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --vnet-name vnet-workload-prod-eastus2 \
  --address-prefixes 10.1.1.0/24 2001:db8:1:1::/64

# Workload Subnet 2
az network vnet subnet create \
  --name snet-workload-02 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --vnet-name vnet-workload-prod-eastus2 \
  --address-prefixes 10.1.2.0/24 2001:db8:1:2::/64

# Management Subnet
az network vnet subnet create \
  --name snet-mgmt \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --vnet-name vnet-workload-prod-eastus2 \
  --address-prefixes 10.1.3.0/24 2001:db8:1:3::/64
```

- [ ] snet-workload-01 created (dual-stack)
- [ ] snet-workload-02 created (dual-stack)
- [ ] snet-mgmt created (dual-stack)

### 3.3 Connect VNet to Virtual Hub

```bash
# Create hub connection
az network vhub connection create \
  --name conn-vnet-workload \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --vhub-name vhub-dualstack-prod-eastus2 \
  --remote-vnet vnet-workload-prod-eastus2 \
  --internet-security true
```

- [ ] VNet connected to hub
- [ ] Routes propagating
- [ ] Internet security enabled

---

## Phase 4: Simulated On-Premises Environment (Optional)

> **Note**: This phase is only needed if using the simulated on-prem environment
> instead of a real on-premises datacenter. Skip to Phase 5 if using real hardware.

### 4.1 Deploy Simulated On-Prem with Terraform

```bash
# Ensure onprem_sim_enabled = true in terraform.tfvars
cd terraform

# Initialize and apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

- [ ] Terraform initialized successfully
- [ ] Plan reviewed and approved
- [ ] Resources deployed

### 4.2 Record Simulated On-Prem Details

After deployment, note these outputs:

```bash
terraform output onprem_vpn_public_ip
terraform output onprem_bgp_asn
terraform output onprem_vpn_private_ip
terraform output onprem_test_vm_private_ip
```

- [ ] VPN VM Public IP: ____________
- [ ] VPN VM Private IP: 192.168.0.4
- [ ] BGP ASN: 65001
- [ ] Test VM Private IP: ____________

### 4.3 Wait for Azure VPN Gateway

The VPN Gateway takes 30-45 minutes to provision. Get its details:

```bash
# Get Azure VPN Gateway public IPs and BGP settings
az network vpn-gateway show \
  --name vpngw-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-prod-eastus2 \
  --query '{
    Instance0_IP: bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0],
    Instance1_IP: bgpSettings.bgpPeeringAddresses[1].tunnelIpAddresses[0],
    BGP_ASN: bgpSettings.asn,
    BGP_IP_0: bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0],
    BGP_IP_1: bgpSettings.bgpPeeringAddresses[1].defaultBgpIpAddresses[0]
  }'
```

- [ ] Azure VPN Gateway Instance 0 IP: ____________
- [ ] Azure VPN Gateway Instance 1 IP: ____________
- [ ] Azure BGP Peer IP 0: ____________
- [ ] Azure BGP Peer IP 1: ____________

### 4.4 Configure strongSwan on VPN VM

SSH to the VPN gateway VM and run the configuration script:

```bash
# SSH to VPN VM
ssh azureuser@<VPN_VM_PUBLIC_IP>

# Run the configuration script
sudo update-vpn-config

# Enter the Azure VPN Gateway details when prompted:
# - Instance 0 Public IP
# - Instance 1 Public IP
# - BGP Peer IP 0
# - BGP Peer IP 1
```

- [ ] SSH connection successful
- [ ] Configuration script completed
- [ ] Services restarted

### 4.5 Verify strongSwan Status

```bash
# On the VPN VM
sudo vpn-status

# Or check individually:
sudo ipsec statusall
sudo vtysh -c "show ip bgp summary"
```

- [ ] IPsec tunnels: ESTABLISHED
- [ ] BGP sessions: ESTABLISHED

### 4.6 Verify Connectivity from Test VM

```bash
# SSH to VPN VM first, then SSH to test VM
ssh azureuser@<VPN_VM_PUBLIC_IP>
ssh <TEST_VM_PRIVATE_IP>

# From test VM, ping Azure workload subnet
ping 10.1.1.4
ping6 2001:db8:1:1::4
```

- [ ] Test VM reachable via VPN VM
- [ ] Ping to Azure VNet: SUCCESS / FAIL

---

## Phase 5: VPN to On-Premises (Real Hardware)

> **Note**: Skip this phase if using simulated on-prem (Phase 4).
> The Terraform configuration handles this automatically when `onprem_sim_enabled = true`.

### 5.1 Create VPN Site

```bash
# Create VPN site for on-premises
az network vpn-site create \
  --name vpnsite-onprem-hq \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --location eastus2 \
  --virtual-wan vwan-dualstack-prod-eastus2 \
  --ip-address <ON-PREM-PUBLIC-IP> \
  --address-prefixes 192.168.0.0/16 2001:db8:2::/48 \
  --with-link true \
  --link-name link-primary \
  --link-speed-in-mbps 100 \
  --link-ip-address <ON-PREM-PUBLIC-IP> \
  --link-provider-name <VENDOR>
```

- [ ] VPN site created
- [ ] On-prem public IP configured
- [ ] Address spaces defined:
  - [ ] IPv4: `192.168.0.0/16`
  - [ ] IPv6: `2001:db8:2::/48`

### 5.2 Configure BGP on VPN Site

```bash
# Update VPN site with BGP settings
az network vpn-site update \
  --name vpnsite-onprem-hq \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --set links[0].bgpProperties.asn=<ON-PREM-ASN> \
  --set links[0].bgpProperties.bgpPeeringAddress=<ON-PREM-BGP-IP>
```

- [ ] BGP ASN configured: ____________
- [ ] BGP peer IP configured: ____________
- [ ] BGP IPv6 peer (if applicable): ____________

### 5.3 Create VPN Connection

```bash
# Get VPN gateway ID
VPNGW_ID=$(az network vpn-gateway show \
  --name vpngw-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --query id -o tsv)

# Create connection
az network vpn-gateway connection create \
  --name conn-onprem-hq \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --gateway-name vpngw-dualstack-prod-eastus2 \
  --remote-vpn-site vpnsite-onprem-hq \
  --enable-bgp true \
  --shared-key "<PRE-SHARED-KEY>" \
  --vpn-site-link /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/vpnSites/vpnsite-onprem-hq/vpnSiteLinks/link-primary
```

- [ ] VPN connection created
- [ ] Pre-shared key configured (store securely)
- [ ] BGP enabled on connection
- [ ] Connection mode: IKEv2

### 5.4 Configure Custom IPsec Policy (Optional)

```bash
# Apply custom IPsec policy
az network vpn-gateway connection ipsec-policy add \
  --connection-name conn-onprem-hq \
  --gateway-name vpngw-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --ike-encryption AES256 \
  --ike-integrity SHA256 \
  --dh-group DHGroup14 \
  --ipsec-encryption GCMAES256 \
  --ipsec-integrity GCMAES256 \
  --pfs-group PFS2048 \
  --sa-lifetime 27000
```

- [ ] Custom IPsec policy applied
- [ ] Policy matches on-prem device configuration

---

## Phase 6: On-Premises Device Configuration (Real Hardware Only)

> **Note**: Skip this phase if using simulated on-prem (Phase 4).

### 6.1 Gather Azure VPN Gateway Details

```bash
# Get gateway IPs and BGP settings
az network vpn-gateway show \
  --name vpngw-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --query '{BGP_ASN:bgpSettings.asn, BGP_IP:bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0], Instance0_IP:ipConfigurations[0].publicIpAddress, Instance1_IP:ipConfigurations[1].publicIpAddress}'
```

Record these values:
- [ ] Azure VPN Gateway Instance 0 IP: ____________
- [ ] Azure VPN Gateway Instance 1 IP: ____________
- [ ] Azure BGP ASN: 65515
- [ ] Azure BGP Peer IP: ____________

### 6.2 Configure On-Premises VPN Device

- [ ] Download VPN device configuration script from Azure Portal
- [ ] Configure IKE Phase 1 settings
- [ ] Configure IKE Phase 2 settings
- [ ] Configure BGP peering
- [ ] Set up IPv4 and IPv6 route advertisements
- [ ] Apply configuration to device

### 6.3 Verify Tunnel Status

- [ ] Tunnel 1 (to Instance 0): UP / DOWN
- [ ] Tunnel 2 (to Instance 1): UP / DOWN
- [ ] BGP session established: YES / NO

---

## Phase 7: Verification & Testing

### 7.1 Verify Routes

```bash
# Check effective routes in hub
az network vhub get-effective-routes \
  --name vhub-dualstack-prod-eastus2 \
  --resource-group rg-dualstack-vwan-prod-eastus2 \
  --resource-type VpnConnection \
  --resource-id <connection-id>
```

- [ ] On-prem routes visible in hub
- [ ] Azure VNet routes visible on on-prem
- [ ] IPv6 routes propagating correctly

### 7.2 Connectivity Tests

From Azure VM:
```bash
# IPv4 ping to on-prem
ping 192.168.1.1

# IPv6 ping to on-prem
ping6 2001:db8:2::1

# Traceroute
traceroute 192.168.1.1
```

- [ ] IPv4 ping to on-prem: SUCCESS / FAIL
- [ ] IPv6 ping to on-prem: SUCCESS / FAIL
- [ ] Traceroute shows expected path

From On-Premises:
```bash
# IPv4 ping to Azure
ping 10.1.1.10

# IPv6 ping to Azure
ping6 2001:db8:1:1::10
```

- [ ] IPv4 ping to Azure: SUCCESS / FAIL
- [ ] IPv6 ping to Azure: SUCCESS / FAIL

### 7.3 BGP Verification

```bash
# Check BGP peer status (on-prem device)
show ip bgp summary
show ipv6 bgp summary
```

- [ ] BGP IPv4 session: ESTABLISHED
- [ ] BGP IPv6 session: ESTABLISHED
- [ ] Routes received from Azure: ____________
- [ ] Routes advertised to Azure: ____________

---

## Phase 8: Monitoring & Documentation

### 8.1 Enable Diagnostics

```bash
# Enable VPN gateway diagnostics
az monitor diagnostic-settings create \
  --name vpn-diag \
  --resource <vpn-gateway-id> \
  --workspace <log-analytics-workspace-id> \
  --logs '[{"category": "GatewayDiagnosticLog", "enabled": true}]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

- [ ] VPN Gateway diagnostics enabled
- [ ] Log Analytics workspace configured
- [ ] Metrics collection enabled

### 8.2 Configure Alerts

- [ ] Alert: VPN tunnel disconnected
- [ ] Alert: BGP peer down
- [ ] Alert: Packet drop threshold exceeded
- [ ] Alert: Bandwidth utilization > 80%

### 8.3 Documentation Updates

- [ ] Update network diagram with final IPs
- [ ] Document on-prem VPN device configuration
- [ ] Record all pre-shared keys in secure vault
- [ ] Create runbook for failover procedures
- [ ] Update CMDB/inventory

---

## Rollback Procedure

If issues occur, rollback in reverse order:

1. Delete VPN connection
2. Delete VPN site
3. Delete VNet-to-Hub connection
4. Delete VNet (if new)
5. Delete VPN Gateway
6. Delete Virtual Hub
7. Delete Virtual WAN
8. Delete Resource Group

```bash
# Quick cleanup (DESTRUCTIVE)
az group delete --name rg-dualstack-vwan-prod-eastus2 --yes --no-wait
```

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Network Engineer | | | |
| Security Review | | | |
| Change Manager | | | |
| Operations Handover | | | |

---

## Notes & Issues

Record any issues encountered during implementation:

| Date | Issue | Resolution | Owner |
|------|-------|------------|-------|
| | | | |
| | | | |
| | | | |
