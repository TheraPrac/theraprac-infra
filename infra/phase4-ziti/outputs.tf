# =============================================================================
# TheraPrac Infrastructure - Phase 4: Ziti Outputs
# =============================================================================

# =============================================================================
# EC2 Instance
# =============================================================================

output "ziti_ec2_id" {
  description = "ID of the Ziti EC2 instance"
  value       = aws_instance.ziti.id
}

output "ziti_availability_zone" {
  description = "Availability zone of the Ziti EC2 instance"
  value       = aws_instance.ziti.availability_zone
}

output "ziti_ec2_private_ip" {
  description = "Private IP of the Ziti EC2 instance"
  value       = aws_instance.ziti.private_ip
}

output "ziti_ec2_private_dns" {
  description = "AWS private DNS of the Ziti EC2 instance"
  value       = aws_instance.ziti.private_dns
}

# =============================================================================
# DNS - Public
# =============================================================================

output "ziti_public_url" {
  description = "Public URL to access Ziti controller (via NLB TCP passthrough)"
  value       = "https://${var.ziti_public_domain}"
}

output "ziti_public_dns_name" {
  description = "Public DNS name for Ziti (Route53 record)"
  value       = aws_route53_record.ziti_public.fqdn
}

# =============================================================================
# DNS - Private (Internal)
# =============================================================================

output "ziti_private_dns_name" {
  description = "Private DNS name for Ziti EC2 instance (internal only)"
  value       = aws_route53_record.ziti_private.fqdn
}

output "internal_zone_name" {
  description = "Private hosted zone name for internal services"
  value       = aws_route53_zone.private.name
}

output "internal_zone_id" {
  description = "Private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

# =============================================================================
# Load Balancer (NLB with TCP Passthrough)
# =============================================================================

output "ziti_nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.ziti.dns_name
}

output "ziti_nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.ziti.arn
}

output "ziti_nlb_zone_id" {
  description = "Zone ID of the Network Load Balancer"
  value       = aws_lb.ziti.zone_id
}

# =============================================================================
# Certificate (not used by NLB - kept for potential future use)
# =============================================================================
# NOTE: With NLB TCP passthrough, the controller presents its own TLS cert.
# The ACM certificate is retained but not attached to the load balancer.

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate (not used by NLB)"
  value       = aws_acm_certificate.ziti.arn
}

output "acm_certificate_domain" {
  description = "Domain name of the ACM certificate"
  value       = aws_acm_certificate.ziti.domain_name
}

# =============================================================================
# Security Groups
# =============================================================================
# NOTE: NLB does not use security groups - only the EC2 instance has one

output "ziti_security_group_id" {
  description = "Security group ID for the Ziti instance"
  value       = aws_security_group.ziti.id
}

# =============================================================================
# EC2 Instance Connect Endpoint (for SSH/Ansible access)
# =============================================================================

output "eice_id" {
  description = "ID of the EC2 Instance Connect Endpoint"
  value       = aws_ec2_instance_connect_endpoint.main.id
}

output "eice_dns_name" {
  description = "DNS name of the EC2 Instance Connect Endpoint"
  value       = aws_ec2_instance_connect_endpoint.main.dns_name
}

output "ssh_command" {
  description = "Command to SSH into the Ziti instance via EICE"
  value       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.ziti.id} --os-user ec2-user --connection-type eice"
}

# =============================================================================
# Ansible Integration
# =============================================================================

output "ansible_host" {
  description = "Ansible host value for inventory"
  value       = aws_instance.ziti.id
}

output "ansible_inventory_hint" {
  description = "Hint for Ansible inventory configuration"
  value       = <<-EOT
    # Preferred: Use Ziti overlay (requires ZDE running)
    # ansible_host: ssh.ziti-${var.environment}.ziti
    #
    # Fallback: Use EICE tunnel
    # ProxyCommand: aws ec2-instance-connect open-tunnel --instance-id ${aws_instance.ziti.id}
  EOT
}

# =============================================================================
# Ziti Service Discovery
# =============================================================================

output "ziti_ssh_hostname" {
  description = "Ziti synthetic DNS name for SSH access"
  value       = "ssh.ziti-${var.environment}.ziti"
}

output "ziti_environment" {
  description = "Ziti environment name (for service naming)"
  value       = var.environment
}
