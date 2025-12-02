# =============================================================================
# TheraPrac Infrastructure - Phase 2: NAT Gateway + S3 Gateway
# =============================================================================
# This module creates:
#   - NAT Gateway in public-az1 for outbound internet access (~$32/month)
#   - S3 Gateway Endpoint (free) for private S3 access
#
# Simplified architecture - NAT Gateway is fully managed by AWS
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

  # Public subnet for NAT Gateway (az1 only for nonprod)
  public_subnet_az1_id = data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az1"]

  # Route tables for non-prod private subnets that need NAT route
  nat_route_table_ids = [
    data.terraform_remote_state.vpc.outputs.route_table_ids["app_nonprod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["db_nonprod"],
    data.terraform_remote_state.vpc.outputs.route_table_ids["ziti_nonprod"],
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
# Elastic IP for NAT Gateway
# =============================================================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "nat-gateway-eip-nonprod"
  }
}

# =============================================================================
# NAT Gateway (Managed by AWS - no configuration needed)
# =============================================================================

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.public_subnet_az1_id

  tags = {
    Name = "nat-gateway-nonprod"
  }

  # Ensure IGW exists before creating NAT Gateway
  depends_on = [data.terraform_remote_state.vpc]
}

# =============================================================================
# Route Table Updates - Add NAT route to nonprod private subnets
# =============================================================================

resource "aws_route" "private_nat" {
  for_each = toset(local.nat_route_table_ids)

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# =============================================================================
# S3 Gateway Endpoint (FREE)
# =============================================================================

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = local.all_route_table_ids

  tags = {
    Name        = "vpce-s3-gateway"
    Description = "S3 gateway endpoint for private S3 access (free)"
  }
}
