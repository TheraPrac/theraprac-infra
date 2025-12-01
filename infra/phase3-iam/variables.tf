# =============================================================================
# TheraPrac Infrastructure - Phase 3: IAM Variables
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

variable "environment" {
  description = "Environment name (nonprod, prod)"
  type        = string
  default     = "nonprod"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "theraprac"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "TheraPrac"
    ManagedBy = "Terraform"
    Phase     = "3-iam"
  }
}

