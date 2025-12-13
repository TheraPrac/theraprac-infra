# =============================================================================
# TheraPrac Infrastructure - Phase 8: Web Artifact Storage Outputs
# =============================================================================

output "bucket_name" {
  description = "Name of the S3 bucket for web artifacts"
  value       = aws_s3_bucket.web_artifacts.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.web_artifacts.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.web_artifacts.bucket_domain_name
}

output "lifecycle_policy_status" {
  description = "Status of lifecycle policies"
  value       = "Environment builds expire after ${var.build_retention_days} days. Latest pointers stay fresh. Releases kept forever."
}




