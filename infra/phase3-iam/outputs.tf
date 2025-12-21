# =============================================================================
# TheraPrac Infrastructure - Phase 3: IAM Outputs
# =============================================================================

# =============================================================================
# Managed Policies
# =============================================================================

output "base_ec2_policy_arn" {
  description = "ARN of the base EC2 managed policy"
  value       = aws_iam_policy.base_ec2.arn
}

output "secrets_read_policy_arn" {
  description = "ARN of the Secrets Manager read-only policy"
  value       = aws_iam_policy.secrets_readonly.arn
}

output "observability_write_policy_arn" {
  description = "ARN of the Observability (CloudWatch Logs + X-Ray) write policy"
  value       = aws_iam_policy.observability_write.arn
}

# =============================================================================
# Ziti Controller
# =============================================================================

output "ziti_controller_role_arn" {
  description = "ARN of the Ziti Controller IAM role"
  value       = aws_iam_role.ziti_controller.arn
}

output "ziti_controller_role_name" {
  description = "Name of the Ziti Controller IAM role"
  value       = aws_iam_role.ziti_controller.name
}

output "ziti_controller_instance_profile_arn" {
  description = "ARN of the Ziti Controller instance profile"
  value       = aws_iam_instance_profile.ziti_controller.arn
}

output "ziti_controller_instance_profile_name" {
  description = "Name of the Ziti Controller instance profile"
  value       = aws_iam_instance_profile.ziti_controller.name
}

# =============================================================================
# Ziti Router
# =============================================================================

output "ziti_router_role_arn" {
  description = "ARN of the Ziti Router IAM role"
  value       = aws_iam_role.ziti_router.arn
}

output "ziti_router_role_name" {
  description = "Name of the Ziti Router IAM role"
  value       = aws_iam_role.ziti_router.name
}

output "ziti_router_instance_profile_arn" {
  description = "ARN of the Ziti Router instance profile"
  value       = aws_iam_instance_profile.ziti_router.arn
}

output "ziti_router_instance_profile_name" {
  description = "Name of the Ziti Router instance profile"
  value       = aws_iam_instance_profile.ziti_router.name
}

# =============================================================================
# App Server
# =============================================================================

output "app_server_role_arn" {
  description = "ARN of the App Server IAM role"
  value       = aws_iam_role.app_server.arn
}

output "app_server_role_name" {
  description = "Name of the App Server IAM role"
  value       = aws_iam_role.app_server.name
}

output "app_server_instance_profile_arn" {
  description = "ARN of the App Server instance profile"
  value       = aws_iam_instance_profile.app_server.arn
}

output "app_server_instance_profile_name" {
  description = "Name of the App Server instance profile"
  value       = aws_iam_instance_profile.app_server.name
}

# =============================================================================
# Summary Map (for convenience)
# =============================================================================

output "instance_profiles" {
  description = "Map of all instance profile names for easy reference"
  value = {
    ziti_controller = aws_iam_instance_profile.ziti_controller.name
    ziti_router     = aws_iam_instance_profile.ziti_router.name
    app_server      = aws_iam_instance_profile.app_server.name
  }
}

output "role_arns" {
  description = "Map of all IAM role ARNs for easy reference"
  value = {
    ziti_controller = aws_iam_role.ziti_controller.arn
    ziti_router     = aws_iam_role.ziti_router.arn
    app_server      = aws_iam_role.app_server.arn
  }
}







