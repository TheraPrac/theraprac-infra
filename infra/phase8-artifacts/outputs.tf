# =============================================================================
# TheraPrac Infrastructure - Phase 8: Artifact Storage Outputs
# =============================================================================

output "artifact_bucket_name" {
  description = "Name of the artifact bucket"
  value       = data.aws_s3_bucket.artifacts.id
}

output "artifact_bucket_arn" {
  description = "ARN of the artifact bucket"
  value       = data.aws_s3_bucket.artifacts.arn
}

output "lifecycle_policy_status" {
  description = "Status of lifecycle policies"
  value       = "Branch builds expire after ${var.branch_build_retention_days} days. Releases kept forever."
}



