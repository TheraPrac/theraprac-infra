# =============================================================================
# TheraPrac Infrastructure - Phase 8: Artifact Storage Variables
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
    Phase       = "8-artifacts"
  }
}

variable "artifact_bucket_name" {
  description = "Name of the S3 bucket for build artifacts"
  type        = string
  default     = "theraprac-api"
}

variable "branch_build_retention_days" {
  description = "Number of days to retain branch builds before deletion"
  type        = number
  default     = 30
}




