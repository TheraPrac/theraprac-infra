# =============================================================================
# TheraPrac Infrastructure - Phase 8: Web Artifact Storage Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "TheraPrac"
    Environment = "shared"
    ManagedBy   = "Terraform"
    Phase       = "8-artifacts-web"
  }
}

variable "bucket_name" {
  description = "Name of the S3 bucket for web build artifacts"
  type        = string
  default     = "theraprac-web"
}

variable "build_retention_days" {
  description = "Number of days to retain environment builds before deletion"
  type        = number
  default     = 30
}

