# =============================================================================
# TheraPrac Infrastructure - Phase 1: VPC & Network Foundation
# =============================================================================
# This module creates:
#   - VPC
#   - Internet Gateway
#   - Public Subnets (3 AZs)
#   - Private App Subnets (Non-Prod: 3 AZs, Prod: 3 AZs)
#   - Private DB Subnets (Non-Prod: 3 AZs, Prod: 3 AZs)
#   - Private Ziti Subnets (Non-Prod: 3 AZs, Prod: 3 AZs)
#   - Route Tables and Associations
# =============================================================================

locals {
  az_keys = keys(var.availability_zones)
}

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = var.vpc_name
  })
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-igw"
  })
}

# =============================================================================
# Public Subnets
# =============================================================================

resource "aws_subnet" "public" {
  for_each = var.public_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "public-${each.key}"
    Tier = "public"
  })
}

# =============================================================================
# Private App Subnets - Non-Prod
# =============================================================================

resource "aws_subnet" "private_app_nonprod" {
  for_each = var.private_app_nonprod_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name        = "private-app-nonprod-${each.key}"
    Tier        = "private"
    Environment = "nonprod"
    Role        = "app"
  })
}

# =============================================================================
# Private DB Subnets - Non-Prod
# =============================================================================

resource "aws_subnet" "private_db_nonprod" {
  for_each = var.private_db_nonprod_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name        = "private-db-nonprod-${each.key}"
    Tier        = "private"
    Environment = "nonprod"
    Role        = "database"
  })
}

# =============================================================================
# Private Ziti Subnets - Non-Prod
# =============================================================================

resource "aws_subnet" "private_ziti_nonprod" {
  for_each = var.private_ziti_nonprod_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name        = "private-ziti-nonprod-${each.key}"
    Tier        = "private"
    Environment = "nonprod"
    Role        = "ziti"
  })
}

# =============================================================================
# Private App Subnets - Prod
# =============================================================================

resource "aws_subnet" "private_app_prod" {
  for_each = var.private_app_prod_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name        = "private-app-prod-${each.key}"
    Tier        = "private"
    Environment = "prod"
    Role        = "app"
  })
}

# =============================================================================
# Private DB Subnets - Prod
# =============================================================================

resource "aws_subnet" "private_db_prod" {
  for_each = var.private_db_prod_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name        = "private-db-prod-${each.key}"
    Tier        = "private"
    Environment = "prod"
    Role        = "database"
  })
}

# =============================================================================
# Private Ziti Subnets - Prod
# =============================================================================

resource "aws_subnet" "private_ziti_prod" {
  for_each = var.private_ziti_prod_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[each.key]
  map_public_ip_on_launch = false

  tags = merge(var.common_tags, {
    Name        = "private-ziti-prod-${each.key}"
    Tier        = "private"
    Environment = "prod"
    Role        = "ziti"
  })
}

# =============================================================================
# Route Tables
# =============================================================================

# Public Route Table (routes to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-rt-public"
  })
}

# Non-Prod App Route Table (local only)
resource "aws_route_table" "private_app_nonprod" {
  vpc_id = aws_vpc.main.id

  # Local route is implicit

  tags = merge(var.common_tags, {
    Name        = "${var.vpc_name}-rt-app-nonprod"
    Environment = "nonprod"
  })
}

# Non-Prod DB Route Table (local only)
resource "aws_route_table" "private_db_nonprod" {
  vpc_id = aws_vpc.main.id

  # Local route is implicit

  tags = merge(var.common_tags, {
    Name        = "${var.vpc_name}-rt-db-nonprod"
    Environment = "nonprod"
  })
}

# Non-Prod Ziti Route Table (NAT route added by Phase 2)
resource "aws_route_table" "private_ziti_nonprod" {
  vpc_id = aws_vpc.main.id

  # Default route (0.0.0.0/0) will be added by Phase 2 to point to NAT instance
  # Local route is implicit

  tags = merge(var.common_tags, {
    Name        = "${var.vpc_name}-rt-ziti-nonprod"
    Environment = "nonprod"
  })
}

# Prod App Route Table (local only)
resource "aws_route_table" "private_app_prod" {
  vpc_id = aws_vpc.main.id

  # Local route is implicit

  tags = merge(var.common_tags, {
    Name        = "${var.vpc_name}-rt-app-prod"
    Environment = "prod"
  })
}

# Prod DB Route Table (local only)
resource "aws_route_table" "private_db_prod" {
  vpc_id = aws_vpc.main.id

  # Local route is implicit

  tags = merge(var.common_tags, {
    Name        = "${var.vpc_name}-rt-db-prod"
    Environment = "prod"
  })
}

# Prod Ziti Route Table (local only - NAT may be added later)
resource "aws_route_table" "private_ziti_prod" {
  vpc_id = aws_vpc.main.id

  # Local route is implicit
  # NOTE: NAT gateway route may be added in future phases

  tags = merge(var.common_tags, {
    Name        = "${var.vpc_name}-rt-ziti-prod"
    Environment = "prod"
  })
}

# =============================================================================
# Route Table Associations
# =============================================================================

# Public Subnet Associations
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Non-Prod App Subnet Associations
resource "aws_route_table_association" "private_app_nonprod" {
  for_each = aws_subnet.private_app_nonprod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app_nonprod.id
}

# Non-Prod DB Subnet Associations
resource "aws_route_table_association" "private_db_nonprod" {
  for_each = aws_subnet.private_db_nonprod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_db_nonprod.id
}

# Non-Prod Ziti Subnet Associations
resource "aws_route_table_association" "private_ziti_nonprod" {
  for_each = aws_subnet.private_ziti_nonprod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_ziti_nonprod.id
}

# Prod App Subnet Associations
resource "aws_route_table_association" "private_app_prod" {
  for_each = aws_subnet.private_app_prod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_app_prod.id
}

# Prod DB Subnet Associations
resource "aws_route_table_association" "private_db_prod" {
  for_each = aws_subnet.private_db_prod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_db_prod.id
}

# Prod Ziti Subnet Associations
resource "aws_route_table_association" "private_ziti_prod" {
  for_each = aws_subnet.private_ziti_prod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_ziti_prod.id
}

