# =============================================================================
# TheraPrac Infrastructure - Phase 4: Ziti Variables
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

variable "environment" {
  description = "Environment name (nonprod, prod)"
  type        = string
  default     = "nonprod"
}

# -----------------------------------------------------------------------------
# DNS Configuration
# -----------------------------------------------------------------------------

variable "route53_public_zone_name" {
  description = "Public Route53 hosted zone name"
  type        = string
  default     = "theraprac.com"
}

variable "route53_private_zone_name" {
  description = "Private Route53 hosted zone name for internal services"
  type        = string
  default     = "theraprac-internal.com"
}

variable "ziti_public_domain" {
  description = "Public domain name for Ziti controller (ALB endpoint)"
  type        = string
  default     = "ziti-nonprod.theraprac.com"
}

# -----------------------------------------------------------------------------
# EC2 Configuration
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for Ziti server (ARM-based for cost efficiency)"
  type        = string
  default     = "t4g.micro"
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
    Phase     = "4-ziti"
  }
}
