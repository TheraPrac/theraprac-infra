# =============================================================================
# TheraPrac Infrastructure - Phase 8: Web Artifact Storage
# =============================================================================
# Manages S3 bucket for web build artifacts with lifecycle policies
#
# This module:
#   - Creates the theraprac-web S3 bucket
#   - Enables versioning
#   - Applies lifecycle policies to auto-delete old builds
#   - Keeps latest pointers and releases forever
#
# S3 Structure:
#   builds/{env}/{branch}/{tag}/   - Environment builds (30 day retention)
#   builds/{env}/{branch}/latest/  - Latest pointers (stay fresh)
#   releases/{tag}/                - Final releases (kept forever)
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
    key            = "phase8-artifacts-web/terraform.tfstate"
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
# S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "web_artifacts" {
  bucket = var.bucket_name

  tags = {
    Name        = var.bucket_name
    Purpose     = "Web build artifacts"
    Application = "theraprac-web"
  }
}

resource "aws_s3_bucket_versioning" "web_artifacts" {
  bucket = aws_s3_bucket.web_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "web_artifacts" {
  bucket = aws_s3_bucket.web_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Lifecycle Configuration
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "web_artifacts" {
  bucket = aws_s3_bucket.web_artifacts.id

  # Rule 1: Delete old environment builds
  # Matches: builds/{env}/{branch}/{tag}/ (not latest pointers)
  # Note: Latest pointers (builds/{env}/{branch}/latest/) are overwritten on each build,
  # so they stay fresh and won't be deleted by this rule.
  rule {
    id     = "delete-old-environment-builds"
    status = "Enabled"

    # Match all objects in builds/ directory
    filter {
      prefix = "builds/"
    }

    # Expire objects older than retention period
    expiration {
      days = var.build_retention_days
    }

    # Also clean up noncurrent versions
    noncurrent_version_expiration {
      noncurrent_days = var.build_retention_days
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Note: Releases (releases/*) have no lifecycle rule applied,
  # which means they are kept forever by default.
}

# =============================================================================
# Server-Side Encryption
# =============================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "web_artifacts" {
  bucket = aws_s3_bucket.web_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

