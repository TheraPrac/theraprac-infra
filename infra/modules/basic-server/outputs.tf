# =============================================================================
# TheraPrac Infrastructure - Basic Server Module Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Instance Information
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.server.id
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.server.private_ip
}

output "private_dns" {
  description = "AWS private DNS of the EC2 instance"
  value       = aws_instance.server.private_dns
}

output "availability_zone" {
  description = "Availability zone of the EC2 instance"
  value       = aws_instance.server.availability_zone
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

output "full_name" {
  description = "Full name in dot notation (e.g., app.mt.nonprod)"
  value       = local.full_name
}

output "hyphen_name" {
  description = "Hyphenated name (e.g., app-mt-nonprod)"
  value       = local.hyphen_name
}

# -----------------------------------------------------------------------------
# DNS
# -----------------------------------------------------------------------------

output "internal_dns" {
  description = "Internal DNS name (e.g., app-mt-nonprod.theraprac-internal.com)"
  value       = local.internal_dns
}

output "internal_dns_fqdn" {
  description = "FQDN from Route53 record"
  value       = aws_route53_record.private.fqdn
}

output "ziti_ssh" {
  description = "Ziti synthetic DNS name for SSH (e.g., ssh.app.mt.nonprod.ziti)"
  value       = local.ziti_ssh
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------

output "security_group_id" {
  description = "Security group ID of the server"
  value       = aws_security_group.server.id
}

# -----------------------------------------------------------------------------
# SSH Commands (for convenience)
# -----------------------------------------------------------------------------

output "ssh_command_ziti" {
  description = "SSH command via Ziti (requires ZDE running)"
  value       = "ssh jfinlinson@${local.ziti_ssh}"
}

output "ssh_command_eice" {
  description = "SSH command via EC2 Instance Connect (break-glass)"
  value       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.server.id} --os-user jfinlinson --connection-type eice"
}

