# =============================================================================
# Variables for GCP On-Prem Simulation
# =============================================================================

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for on-prem simulation"
  type        = string
  default     = "us-west1"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

variable "router_machine_type" {
  description = "Machine type for router VMs"
  type        = string
  default     = "e2-medium"  # 2 vCPU, 4GB RAM - sufficient for VPN routing
}

variable "test_vm_machine_type" {
  description = "Machine type for test VM"
  type        = string
  default     = "e2-micro"  # 0.25 vCPU, 1GB RAM - just for ping tests
}
