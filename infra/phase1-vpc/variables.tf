# =============================================================================
# AWS Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "jfinlinson_cli"
}

# =============================================================================
# VPC Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "theraprac-vpc"
}

# =============================================================================
# Availability Zones
# =============================================================================

variable "availability_zones" {
  description = "Map of AZ aliases to actual AZ names"
  type        = map(string)
  default = {
    az1 = "us-west-2a"
    az2 = "us-west-2b"
    az3 = "us-west-2c"
  }
}

# =============================================================================
# Subnet CIDRs - Public
# =============================================================================

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = map(string)
  default = {
    az1 = "10.20.0.0/24"
    az2 = "10.20.1.0/24"
    az3 = "10.20.2.0/24"
  }
}

# =============================================================================
# Subnet CIDRs - Non-Prod
# =============================================================================

variable "private_app_nonprod_subnet_cidrs" {
  description = "CIDR blocks for non-prod app subnets"
  type        = map(string)
  default = {
    az1 = "10.20.10.0/24"
    az2 = "10.20.11.0/24"
    az3 = "10.20.12.0/24"
  }
}

variable "private_db_nonprod_subnet_cidrs" {
  description = "CIDR blocks for non-prod database subnets"
  type        = map(string)
  default = {
    az1 = "10.20.20.0/24"
    az2 = "10.20.21.0/24"
    az3 = "10.20.22.0/24"
  }
}

variable "private_ziti_nonprod_subnet_cidrs" {
  description = "CIDR blocks for non-prod Ziti subnets"
  type        = map(string)
  default = {
    az1 = "10.20.30.0/24"
    az2 = "10.20.31.0/24"
    az3 = "10.20.32.0/24"
  }
}

# =============================================================================
# Subnet CIDRs - Prod
# =============================================================================

variable "private_app_prod_subnet_cidrs" {
  description = "CIDR blocks for prod app subnets"
  type        = map(string)
  default = {
    az1 = "10.20.50.0/24"
    az2 = "10.20.51.0/24"
    az3 = "10.20.52.0/24"
  }
}

variable "private_db_prod_subnet_cidrs" {
  description = "CIDR blocks for prod database subnets"
  type        = map(string)
  default = {
    az1 = "10.20.60.0/24"
    az2 = "10.20.61.0/24"
    az3 = "10.20.62.0/24"
  }
}

variable "private_ziti_prod_subnet_cidrs" {
  description = "CIDR blocks for prod Ziti subnets"
  type        = map(string)
  default = {
    az1 = "10.20.70.0/24"
    az2 = "10.20.71.0/24"
    az3 = "10.20.72.0/24"
  }
}

# =============================================================================
# Resource Tags
# =============================================================================

variable "common_tags" {
  description = "Common tags applied to all resources (in addition to provider default_tags)"
  type        = map(string)
  default = {
    Phase = "1-network"
  }
}

