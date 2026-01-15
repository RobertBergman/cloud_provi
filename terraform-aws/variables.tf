# =============================================================================
# Variables for AWS Dual-Stack VPN Infrastructure
# =============================================================================

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

# =============================================================================
# On-Prem Router Configuration (from terraform-onprem-sim outputs)
# =============================================================================

variable "router_1_public_ip" {
  description = "Public IP of on-prem router 1 (from terraform-onprem-sim output)"
  type        = string
}

variable "router_2_public_ip" {
  description = "Public IP of on-prem router 2 (from terraform-onprem-sim output)"
  type        = string
}

variable "onprem_bgp_asn" {
  description = "BGP ASN for on-prem routers"
  type        = number
  default     = 65001
}

# =============================================================================
# Instance Configuration
# =============================================================================

variable "test_instance_type" {
  description = "EC2 instance type for test instance"
  type        = string
  default     = "t3.micro"
}
