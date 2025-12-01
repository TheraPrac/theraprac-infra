# =============================================================================
# TheraPrac Infrastructure - Phase 0: Bootstrap Variables
# =============================================================================

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "jfinlinson_cli"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name (will have random suffix appended)"
  type        = string
  default     = "theraprac-tfstate"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "theraprac-terraform-locks"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "TheraPrac"
    ManagedBy = "Terraform"
    Phase     = "0-bootstrap"
  }
}

