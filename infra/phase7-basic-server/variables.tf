# =============================================================================
# TheraPrac Infrastructure - Phase 7: Basic Server Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "jfinlinson_admin"
}

# -----------------------------------------------------------------------------
# Server Identity (passed from provision script)
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
  default     = "app"
}

variable "environment" {
  description = "Environment: prod, nonprod, dev, test, stage, uat"
  type        = string
  default     = "nonprod"
  validation {
    condition     = contains(["prod", "nonprod", "dev", "test", "stage", "uat"], var.environment)
    error_message = "Environment must be one of: prod, nonprod, dev, test, stage, uat"
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
}

# -----------------------------------------------------------------------------
# SSH Keys (Sensitive - loaded from tfvars)
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
# Tags
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "TheraPrac"
    ManagedBy = "Terraform"
    Phase     = "7-basic-server"
  }
}


