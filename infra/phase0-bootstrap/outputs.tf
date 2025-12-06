# =============================================================================
# TheraPrac Infrastructure - Phase 0: Bootstrap Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = var.aws_region
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.arn
}

# =============================================================================
# Backend Configuration Block (for use in other modules)
# =============================================================================

output "backend_config" {
  description = "Backend configuration block to use in other Terraform modules"
  value       = <<-EOT

    # =============================================================================
    # S3 Backend Configuration
    # =============================================================================
    # Copy this block to your module's backend.tf file, then run:
    #   terraform init -migrate-state
    # =============================================================================

    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        key            = "CHANGE_ME/terraform.tfstate"  # e.g., "phase1-vpc/terraform.tfstate"
        region         = "${var.aws_region}"
        profile        = "${var.aws_profile}"
        encrypt        = true
        dynamodb_table = "${aws_dynamodb_table.terraform_locks.name}"
      }
    }

  EOT
}



