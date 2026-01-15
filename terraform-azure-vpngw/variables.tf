# =============================================================================
# Azure VPN Gateway - Variables
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., prod, dev)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "vnet_ipv4_cidr" {
  description = "IPv4 CIDR for the Azure VNet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "vnet_ipv6_cidr" {
  description = "IPv6 CIDR for the Azure VNet (ULA)"
  type        = string
  default     = "fd20:d:1::/48"
}

# -----------------------------------------------------------------------------
# On-Premises Configuration (from GCP simulation)
# -----------------------------------------------------------------------------

variable "router_1_public_ip" {
  description = "Public IP of on-prem router 1 (from terraform-onprem-sim output)"
  type        = string
}

variable "router_2_public_ip" {
  description = "Public IP of on-prem router 2 (from terraform-onprem-sim output)"
  type        = string
}

variable "onprem_bgp_asn" {
  description = "BGP ASN for on-premises routers"
  type        = number
  default     = 65001
}

variable "onprem_ipv4_ranges" {
  description = "IPv4 CIDR ranges for on-premises network"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "onprem_ipv6_ranges" {
  description = "IPv6 CIDR ranges for on-premises network"
  type        = list(string)
  default     = ["fd20:e:1::/48"]
}

# -----------------------------------------------------------------------------
# VPN Configuration
# -----------------------------------------------------------------------------

variable "vpn_shared_key" {
  description = "Pre-shared key for IPsec VPN tunnels"
  type        = string
  sensitive   = true
}

variable "vpn_gateway_sku" {
  description = "SKU for VPN Gateway (VpnGw1 or higher for IPv6 support)"
  type        = string
  default     = "VpnGw1"
}

variable "enable_active_active" {
  description = "Enable Active-Active VPN Gateway (2 public IPs)"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Test VM Configuration
# -----------------------------------------------------------------------------

variable "test_vm_admin_username" {
  description = "Admin username for test VM"
  type        = string
  default     = "azureuser"
}

variable "test_vm_ssh_public_key" {
  description = "SSH public key for test VM authentication"
  type        = string
}

variable "test_vm_size" {
  description = "Size of the test VM"
  type        = string
  default     = "Standard_B1s"
}
