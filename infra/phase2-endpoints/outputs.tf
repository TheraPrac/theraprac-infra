# =============================================================================
# TheraPrac Infrastructure - Phase 2 Outputs
# =============================================================================

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway public IP address"
  value       = aws_eip.nat.public_ip
}

output "s3_gateway_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3_gateway.id
}
