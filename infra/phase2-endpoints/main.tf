# =============================================================================
# TheraPrac Infrastructure - Phase 2: NAT Instance + S3 Gateway
# =============================================================================
# This module creates:
#   - NAT Instance (t4g.nano) in public-az1 for outbound internet access
#   - S3 Gateway Endpoint (free) for private S3 access
#
# Cost-optimized architecture for non-prod:
#   - NAT Instance (~$3/month) instead of NAT Gateway (~$32/month)
#   - Only az1 private subnets route through NAT
#   - No interface endpoints (saves ~$130/month)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "theraprac-tfstate-32fcc26f"
    key            = "phase2-endpoints/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "theraprac-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# =============================================================================
# Remote State Data Source - Import Phase 1 VPC Outputs
# =============================================================================

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "theraprac-tfstate-32fcc26f"
    key    = "phase1-vpc/terraform.tfstate"
    region = "us-west-2"
  }
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  # Public subnet for NAT instance (az1 only)
  public_subnet_az1_id = data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az1"]

  # Route tables for non-prod private subnets that need NAT route
  # Note: ziti_nonprod already has IGW route (for Ziti overlay network)
  nat_route_table_ids = [
    data.terraform_remote_state.vpc.outputs.route_table_ids["app_nonprod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["db_nonprod"],
  ]

  # All route tables for S3 gateway endpoint
  all_route_table_ids = [
    data.terraform_remote_state.vpc.outputs.route_table_ids["public"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["app_nonprod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["db_nonprod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["ziti_nonprod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["app_prod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["db_prod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["ziti_prod"],
  ]
}

# =============================================================================
# AMI Data Source - Latest Amazon Linux 2 (ARM64 for t4g)
# =============================================================================

data "aws_ami" "amazon_linux_2_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# =============================================================================
# Security Group for NAT Instance
# =============================================================================

resource "aws_security_group" "nat_instance" {
  name        = "nat-instance-nonprod"
  description = "Security group for NAT instance"
  vpc_id      = local.vpc_id

  tags = {
    Name = "nat-instance-nonprod"
  }
}

# Inbound: Allow all traffic from VPC (private subnets need to route through)
resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc" {
  security_group_id = aws_security_group.nat_instance.id

  description = "Allow all inbound from VPC for NAT"
  ip_protocol = "-1"
  cidr_ipv4   = var.vpc_cidr

  tags = {
    Name = "nat-from-vpc"
  }
}

# Outbound: Allow all traffic to internet (NAT needs to forward)
resource "aws_vpc_security_group_egress_rule" "nat_to_internet" {
  security_group_id = aws_security_group.nat_instance.id

  description = "Allow all outbound to internet"
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "nat-to-internet"
  }
}

# =============================================================================
# NAT Instance
# =============================================================================

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux_2_arm.id
  instance_type               = var.nat_instance_type
  subnet_id                   = local.public_subnet_az1_id
  associate_public_ip_address = true
  source_dest_check           = false # Required for NAT instance

  vpc_security_group_ids = [aws_security_group.nat_instance.id]

  # User data to enable IP forwarding and NAT
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

    # Configure iptables for NAT (MASQUERADE)
    yum install -y iptables-services
    systemctl enable iptables
    systemctl start iptables

    # Get the primary network interface
    INTERFACE=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -1 | tr -d '/')
    ETH=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens)' | head -1)

    # Set up NAT rules
    iptables -t nat -A POSTROUTING -o $ETH -s ${var.vpc_cidr} -j MASQUERADE
    iptables -A FORWARD -i $ETH -o $ETH -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i $ETH -o $ETH -j ACCEPT

    # Save iptables rules
    service iptables save
  EOF

  tags = {
    Name = "nat-instance-nonprod-az1"
  }

  lifecycle {
    ignore_changes = [ami] # Don't replace on AMI updates
  }
}

# =============================================================================
# Route Table Updates - Add NAT route to az1 non-prod private subnets
# =============================================================================

resource "aws_route" "private_nat" {
  for_each = toset(local.nat_route_table_ids)

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# =============================================================================
# S3 Gateway Endpoint (FREE)
# =============================================================================

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.us-west-2.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = local.all_route_table_ids

  tags = {
    Name        = "vpce-s3-gateway"
    Description = "S3 gateway endpoint for private S3 access (free)"
  }
}
