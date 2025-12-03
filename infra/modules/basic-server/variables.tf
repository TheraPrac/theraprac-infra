# =============================================================================
# TheraPrac Infrastructure - Basic Server Module Variables
# =============================================================================
# Reusable module for creating private EC2 instances accessible via Ziti SSH.
# =============================================================================

# -----------------------------------------------------------------------------
# Server Identity
# -----------------------------------------------------------------------------

variable "name" {
  description = "Server purpose (e.g., 'app')"
  type        = string
}

variable "role" {
  description = "Specific identifier/team (e.g., 'mt')"
  type        = string
}

variable "tier" {
  description = "Subnet tier: app, db, or ziti"
  type        = string
  validation {
    condition     = contains(["app", "db", "ziti"], var.tier)
    error_message = "Tier must be one of: app, db, ziti"
  }
}

variable "environment" {
  description = "Environment: nonprod or prod"
  type        = string
  default     = "nonprod"
  validation {
    condition     = contains(["nonprod", "prod"], var.environment)
    error_message = "Environment must be one of: nonprod, prod"
  }
}

# -----------------------------------------------------------------------------
# Instance Configuration
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.micro"
}

variable "arch" {
  description = "CPU architecture: arm64 or x86_64"
  type        = string
  default     = "arm64"
  validation {
    condition     = contains(["arm64", "x86_64"], var.arch)
    error_message = "Architecture must be one of: arm64, x86_64"
  }
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

# -----------------------------------------------------------------------------
# SSH Keys (Sensitive)
# -----------------------------------------------------------------------------

variable "ssh_key_ansible" {
  description = "SSH public key for ansible automation user"
  type        = string
  sensitive   = true
}

variable "ssh_key_jfinlinson" {
  description = "SSH public key for jfinlinson admin user"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Network Configuration (from remote state)
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID to deploy into"
  type        = string
}

variable "internal_zone_id" {
  description = "Route53 private hosted zone ID"
  type        = string
}

variable "internal_zone_name" {
  description = "Route53 private hosted zone name (e.g., theraprac-internal.com)"
  type        = string
  default     = "theraprac-internal.com"
}

variable "eice_security_group_id" {
  description = "Security group ID of EC2 Instance Connect Endpoint"
  type        = string
}

variable "ziti_subnet_cidr" {
  description = "CIDR of Ziti subnet (for SSH access from router)"
  type        = string
}

# -----------------------------------------------------------------------------
# IAM Configuration
# -----------------------------------------------------------------------------

variable "instance_profile_name" {
  description = "IAM instance profile name for the EC2 instance"
  type        = string
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

