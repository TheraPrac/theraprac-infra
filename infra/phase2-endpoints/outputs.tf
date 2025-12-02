# =============================================================================
# TheraPrac Infrastructure - Phase 2: NAT Instance + S3 Gateway Outputs
# =============================================================================

# =============================================================================
# NAT Instance
# =============================================================================

output "nat_instance_id" {
  description = "ID of the NAT instance"
  value       = aws_instance.nat.id
}

output "nat_instance_public_ip" {
  description = "Public IP of the NAT instance"
  value       = aws_instance.nat.public_ip
}

output "nat_instance_private_ip" {
  description = "Private IP of the NAT instance"
  value       = aws_instance.nat.private_ip
}

output "nat_instance_network_interface_id" {
  description = "Primary network interface ID of the NAT instance"
  value       = aws_instance.nat.primary_network_interface_id
}

# =============================================================================
# Security Group
# =============================================================================

output "nat_security_group_id" {
  description = "ID of the NAT instance security group"
  value       = aws_security_group.nat_instance.id
}

# =============================================================================
# S3 Gateway Endpoint
# =============================================================================

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 gateway endpoint"
  value       = aws_vpc_endpoint.s3_gateway.id
}

# =============================================================================
# AMI Information
# =============================================================================

output "nat_ami_id" {
  description = "AMI ID used for NAT instance"
  value       = data.aws_ami.amazon_linux_2023_arm.id
}

output "nat_ami_name" {
  description = "AMI name used for NAT instance"
  value       = data.aws_ami.amazon_linux_2023_arm.name
}
