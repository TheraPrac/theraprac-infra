# =============================================================================
# TheraPrac Infrastructure - Phase 2: NAT Gateway + S3 Gateway
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
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
