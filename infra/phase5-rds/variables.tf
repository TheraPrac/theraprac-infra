# =============================================================================
# TheraPrac Infrastructure - Phase 5: RDS Variables
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
  description = "Environment: prod, nonprod, dev, test, stage, uat"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["prod", "nonprod", "dev", "test", "stage", "uat"], var.environment)
    error_message = "Environment must be one of: prod, nonprod, dev, test, stage, uat"
  }
}

variable "edge_router_environment" {
  description = "Environment of the edge-router that hosts the database service (nonprod or prod)"
  type        = string
  default     = "nonprod"
  validation {
    condition     = contains(["nonprod", "prod"], var.edge_router_environment)
    error_message = "Edge router environment must be one of: nonprod, prod"
  }
}

# -----------------------------------------------------------------------------
# Database Configuration
# -----------------------------------------------------------------------------

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "theraprac"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage allocation in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage for autoscaling in GB"
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Preferred AZ for single-AZ deployment"
  type        = string
  default     = "us-west-2a"
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 1
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = false
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
    Phase     = "5-rds"
  }
}

