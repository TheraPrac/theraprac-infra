# =============================================================================
# TheraPrac Infrastructure - Phase 8: Artifact Storage
# =============================================================================
# Manages S3 bucket for build artifacts with lifecycle policies
#
# This module:
#   - Applies lifecycle policies to existing theraprac-api bucket
#   - Auto-deletes old branch builds (30 days)
#   - Keeps latest pointers and releases forever
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "theraprac-tfstate-32fcc26f"
    key            = "phase8-artifacts/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "theraprac-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# =============================================================================
# Data Sources
# =============================================================================

# Get existing bucket (assumes it already exists)
data "aws_s3_bucket" "artifacts" {
  bucket = var.artifact_bucket_name
}

# =============================================================================
# S3 Lifecycle Configuration
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = data.aws_s3_bucket.artifacts.id

  # Rule 1: Delete old branch builds (individual commits only)
  # This rule expires objects in builds/{branch}/{commit}/ paths
  # Note: Latest pointers (builds/{branch}/latest/) are overwritten on each build,
  # so they stay fresh and won't be deleted by this rule.
  rule {
    id     = "delete-old-branch-builds"
    status = "Enabled"

    # Match all objects in builds/ directory
    # Latest pointers stay fresh because they're overwritten on each build
    filter {
      prefix = "builds/"
    }

    # Expire objects older than retention period
    expiration {
      days = var.branch_build_retention_days
    }

    # Also clean up noncurrent versions (if versioning is enabled)
    noncurrent_version_expiration {
      noncurrent_days = var.branch_build_retention_days
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Rule 2: Keep releases forever (no expiration)
  # Matches: releases/*
  rule {
    id     = "keep-releases-forever"
    status = "Enabled"

    filter {
      prefix = "releases/"
    }

    # No expiration - releases are immutable and kept forever
  }
}


