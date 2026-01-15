# =============================================================================
# AWS Dual-Stack VPN Infrastructure
# =============================================================================
# Tests AWS Site-to-Site VPN with dual-stack (IPv4 + IPv6) support
# Uses Transit Gateway (required for IPv6 VPN support)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Network ranges
  vpc_ipv4_cidr      = "10.0.0.0/16"
  workload_subnet    = "10.0.1.0/24"
  tgw_subnet         = "10.0.255.0/24"

  # BGP
  aws_asn = 64512

  # On-prem ranges (for route tables)
  onprem_ipv4_cidr = "192.168.0.0/16"
  onprem_ipv6_cidr = "fd20:c:1::/48"

  # Naming
  name_suffix = var.environment

  # Common tags
  common_tags = {
    Project     = "dual-stack-vpn-test"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# VPC with IPv6
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block                       = local.vpc_ipv4_cidr
  enable_dns_hostnames             = true
  enable_dns_support               = true
  assign_generated_ipv6_cidr_block = true  # Request Amazon-provided /56

  tags = merge(local.common_tags, {
    Name = "vpc-aws-${local.name_suffix}"
  })
}

# =============================================================================
# Subnets
# =============================================================================

# Workload subnet (dual-stack)
resource "aws_subnet" "workload" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = local.workload_subnet
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 1)
  availability_zone               = "${var.region}a"
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = merge(local.common_tags, {
    Name = "subnet-workload-${local.name_suffix}"
  })
}

# Transit Gateway attachment subnet
resource "aws_subnet" "tgw" {
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = local.tgw_subnet
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 255)
  availability_zone               = "${var.region}a"
  assign_ipv6_address_on_creation = true

  tags = merge(local.common_tags, {
    Name = "subnet-tgw-${local.name_suffix}"
  })
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "igw-${local.name_suffix}"
  })
}

# =============================================================================
# Route Tables
# =============================================================================

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  # Default route to Internet Gateway (IPv4)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  # Default route to Internet Gateway (IPv6)
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  # Route to on-prem via Transit Gateway (IPv4)
  route {
    cidr_block         = local.onprem_ipv4_cidr
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  # Route to on-prem via Transit Gateway (IPv6)
  route {
    ipv6_cidr_block    = local.onprem_ipv6_cidr
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  # Route for VPN tunnel inside CIDRs (ULA fd00::/8) via Transit Gateway
  # Required for return traffic when source is VTI IPv6 address
  route {
    ipv6_cidr_block    = "fd00::/8"
    transit_gateway_id = aws_ec2_transit_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "rtb-main-${local.name_suffix}"
  })

  depends_on = [aws_ec2_transit_gateway.main]
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "tgw" {
  subnet_id      = aws_subnet.tgw.id
  route_table_id = aws_route_table.main.id
}

# =============================================================================
# Transit Gateway (Required for IPv6 VPN)
# =============================================================================

resource "aws_ec2_transit_gateway" "main" {
  description                     = "Transit Gateway for dual-stack VPN"
  amazon_side_asn                 = local.aws_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.common_tags, {
    Name = "tgw-${local.name_suffix}"
  })
}

# TGW VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  subnet_ids         = [aws_subnet.tgw.id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.main.id
  ipv6_support       = "enable"  # Required for IPv6 route propagation

  tags = merge(local.common_tags, {
    Name = "tgw-attach-vpc-${local.name_suffix}"
  })
}


# =============================================================================
# Customer Gateways (On-Prem Routers)
# =============================================================================

resource "aws_customer_gateway" "router_1" {
  bgp_asn    = var.onprem_bgp_asn
  ip_address = var.router_1_public_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "cgw-router-1-${local.name_suffix}"
  })
}

resource "aws_customer_gateway" "router_2" {
  bgp_asn    = var.onprem_bgp_asn
  ip_address = var.router_2_public_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "cgw-router-2-${local.name_suffix}"
  })
}

# =============================================================================
# VPN Connections
# =============================================================================

# IPv6 VPN Connection - Router 1
# Note: AWS requires separate VPN connections for IPv4 and IPv6 traffic
resource "aws_vpn_connection" "router_1" {
  customer_gateway_id = aws_customer_gateway.router_1.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"

  # Enable BGP
  static_routes_only = false

  # IPv6-only tunnel (traffic selectors: ::/0)
  tunnel_inside_ip_version = "ipv6"
  enable_acceleration      = false

  # Tunnel options
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [14]

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [14]

  tags = merge(local.common_tags, {
    Name = "vpn-router-1-ipv6-${local.name_suffix}"
  })
}

# IPv4 VPN Connection - Router 1
resource "aws_vpn_connection" "router_1_ipv4" {
  customer_gateway_id = aws_customer_gateway.router_1.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"

  # Enable BGP
  static_routes_only = false

  # IPv4-only tunnel (traffic selectors: 0.0.0.0/0)
  tunnel_inside_ip_version = "ipv4"
  enable_acceleration      = false

  # Tunnel options (same as IPv6)
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [14]

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [14]

  tags = merge(local.common_tags, {
    Name = "vpn-router-1-ipv4-${local.name_suffix}"
  })
}

# IPv6 VPN Connection - Router 2
resource "aws_vpn_connection" "router_2" {
  customer_gateway_id = aws_customer_gateway.router_2.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"

  # Enable BGP
  static_routes_only = false

  # IPv6-only tunnel (traffic selectors: ::/0)
  tunnel_inside_ip_version = "ipv6"
  enable_acceleration      = false

  # Tunnel options
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [14]

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [14]

  tags = merge(local.common_tags, {
    Name = "vpn-router-2-ipv6-${local.name_suffix}"
  })
}

# IPv4 VPN Connection - Router 2
resource "aws_vpn_connection" "router_2_ipv4" {
  customer_gateway_id = aws_customer_gateway.router_2.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"

  # Enable BGP
  static_routes_only = false

  # IPv4-only tunnel (traffic selectors: 0.0.0.0/0)
  tunnel_inside_ip_version = "ipv4"
  enable_acceleration      = false

  # Tunnel options
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [14]

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [14]

  tags = merge(local.common_tags, {
    Name = "vpn-router-2-ipv4-${local.name_suffix}"
  })
}

# =============================================================================
# Security Groups
# =============================================================================

resource "aws_security_group" "test_instance" {
  name        = "test-instance-${local.name_suffix}"
  description = "Security group for test EC2 instance"
  vpc_id      = aws_vpc.main.id

  # SSH from anywhere (for testing)
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ICMP from on-prem (IPv4)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [local.onprem_ipv4_cidr]
  }

  # ICMPv6 from on-prem (includes VPN tunnel addresses)
  ingress {
    from_port        = -1
    to_port          = -1
    protocol         = "icmpv6"
    ipv6_cidr_blocks = [local.onprem_ipv6_cidr, "fd00::/8"]  # ULA range for VPN tunnels
  }

  # All traffic from VPC (internal)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.vpc_ipv4_cidr]
  }

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  # Egress - allow all
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.common_tags, {
    Name = "test-instance-sg-${local.name_suffix}"
  })
}

# =============================================================================
# EC2 Test Instance
# =============================================================================

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "test" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.test_instance_type
  subnet_id                   = aws_subnet.workload.id
  vpc_security_group_ids      = [aws_security_group.test_instance.id]
  associate_public_ip_address = true
  ipv6_address_count          = 1

  # Assign specific private IP for easier testing
  private_ip = "10.0.1.100"

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y tcpdump traceroute mtr
    echo "AWS Test Instance Ready" > /tmp/ready
  EOF

  tags = merge(local.common_tags, {
    Name = "ec2-test-${local.name_suffix}"
  })
}
