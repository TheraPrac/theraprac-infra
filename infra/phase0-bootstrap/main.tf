# =============================================================================
# TheraPrac Infrastructure - Phase 0: Bootstrap (Terraform State Backend)
# =============================================================================
# This module creates the infrastructure needed for remote Terraform state:
#   - S3 bucket for state storage (versioned, encrypted, private)
#   - DynamoDB table for state locking
#
# IMPORTANT: This module uses local state. After applying, migrate other
# modules to use the S3 backend created here.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Bootstrap module intentionally uses local state
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = var.common_tags
  }
}

# =============================================================================
# Random Suffix for Globally Unique Bucket Name
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# =============================================================================
# S3 Bucket for Terraform State
# =============================================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"

  # Prevent accidental deletion of this bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
    Description = "Terraform state storage for TheraPrac infrastructure"
  }
}

# -----------------------------------------------------------------------------
# Bucket Versioning - Required for state history and recovery
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# Server-Side Encryption - AES256 at rest
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# -----------------------------------------------------------------------------
# Block All Public Access
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Disable ACLs - Bucket owner enforced
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# -----------------------------------------------------------------------------
# Bucket Policy - Enforce encryption in transit (HTTPS only)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  # Ensure public access block is applied first
  depends_on = [aws_s3_bucket_public_access_block.terraform_state]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceHTTPS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "EnforceEncryptedUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.terraform_state.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      }
    ]
  })
}

# =============================================================================
# DynamoDB Table for State Locking
# =============================================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PROVISIONED"

  read_capacity  = 1
  write_capacity = 1

  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Server-side encryption enabled by default with AWS owned key
  server_side_encryption {
    enabled = true
  }

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = var.dynamodb_table_name
    Description = "Terraform state locking for TheraPrac infrastructure"
  }
}







