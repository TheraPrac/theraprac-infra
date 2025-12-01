# =============================================================================
# TheraPrac Infrastructure - Phase 2: NAT Instance + S3 Gateway
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (for security group rules)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "nat_instance_type" {
  description = "Instance type for NAT instance (cost-optimized)"
  type        = string
  default     = "t4g.nano"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "TheraPrac"
    Environment = "nonprod"
    ManagedBy   = "Terraform"
    Phase       = "2-nat-gateway"
  }
}
