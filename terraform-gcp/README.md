# GCP Dual-Stack VPN Infrastructure

Site-to-Site VPN with BGP between two VPCs simulating cloud and on-premises connectivity.

## Features

- **Dual-Stack Support**: IPv4 + IPv6 throughout (GCP HA VPN supports dual-stack natively)
- **HA VPN**: High-availability VPN with 2 tunnels for 99.99% SLA
- **BGP Dynamic Routing**: Automatic route exchange between VPCs
- **Simulated On-Prem**: Second VPC in different region acts as on-premises

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GCP Project                                     │
├─────────────────────────────────┬───────────────────────────────────────────┤
│       Cloud VPC (us-central1)   │      On-Prem VPC (us-east1)               │
│                                 │                                            │
│  ┌─────────────────────────┐   │   ┌─────────────────────────┐              │
│  │  subnet-workload        │   │   │  subnet-onprem-workload │              │
│  │  10.1.1.0/24 + IPv6     │   │   │  192.168.1.0/24 + IPv6  │              │
│  │                         │   │   │                         │              │
│  │  ┌─────────────────┐    │   │   │    ┌─────────────────┐  │              │
│  │  │ vm-cloud-test   │    │   │   │    │ vm-onprem-test  │  │              │
│  │  └─────────────────┘    │   │   │    └─────────────────┘  │              │
│  └─────────────────────────┘   │   └─────────────────────────┘              │
│              │                  │                │                           │
│              ▼                  │                ▼                           │
│  ┌─────────────────────────┐   │   ┌─────────────────────────┐              │
│  │  HA VPN Gateway         │◄──┼──►│  HA VPN Gateway         │              │
│  │  (IPV4_IPV6 stack)      │   │   │  (IPV4_IPV6 stack)      │              │
│  └─────────────────────────┘   │   └─────────────────────────┘              │
│              │                  │                │                           │
│              ▼                  │                ▼                           │
│  ┌─────────────────────────┐   │   ┌─────────────────────────┐              │
│  │  Cloud Router           │◄──┼──►│  On-Prem Router         │              │
│  │  ASN: 65001             │   │   │  ASN: 65002             │              │
│  │  BGP: IPv4 + IPv6       │   │   │  BGP: IPv4 + IPv6       │              │
│  └─────────────────────────┘   │   └─────────────────────────┘              │
│                                 │                                            │
└─────────────────────────────────┴───────────────────────────────────────────┘
```

## Requirements

- GCP Project with billing enabled
- APIs enabled: Compute Engine
- gcloud CLI authenticated

## Quick Start

```bash
cd terraform-gcp

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID

# Deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Test connectivity
terraform output test_commands
```

## Key Differences from Azure

| Feature | Azure VWAN | GCP HA VPN |
|---------|------------|------------|
| IPv6 VPN Site | ❌ Not supported | ✅ Supported |
| IPv6 over IPsec | ❌ IPv4 only | ✅ Dual-stack |
| IPv6 BGP | ❌ Not supported | ✅ Supported |
| HA/Redundancy | Active-Active | Active-Active |
| Deployment Time | 30-45 min | 5-10 min |

## Verify Deployment

```bash
# Check VPN tunnel status
gcloud compute vpn-tunnels list

# Check BGP sessions
gcloud compute routers get-status router-cloud-prod --region=us-central1

# SSH to cloud VM and ping on-prem
gcloud compute ssh vm-cloud-test-prod --zone=us-central1-a
ping <onprem-internal-ip>
ping6 <onprem-internal-ipv6>
```

## Cleanup

```bash
terraform destroy
```
