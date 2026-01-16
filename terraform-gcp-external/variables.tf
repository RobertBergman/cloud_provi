# =============================================================================
# Variables
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for cloud resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (e.g., prod, dev, test)"
  type        = string
  default     = "prod"
}

variable "vpn_shared_secret" {
  description = "IPsec pre-shared key for VPN tunnels"
  type        = string
  sensitive   = true
}

variable "onprem_router_1_ip" {
  description = "Public IP of on-prem router 1 (from terraform-onprem-sim output)"
  type        = string
}

variable "onprem_router_2_ip" {
  description = "Public IP of on-prem router 2 (from terraform-onprem-sim output)"
  type        = string
}
