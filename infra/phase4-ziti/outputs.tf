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
  description = "Public URL to access Ziti controller (via ALB)"
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
# Load Balancer
# =============================================================================

output "ziti_alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.ziti.dns_name
}

output "ziti_alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.ziti.arn
}

output "ziti_alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.ziti.zone_id
}

# =============================================================================
# Certificate
# =============================================================================

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.ziti.arn
}

output "acm_certificate_domain" {
  description = "Domain name of the ACM certificate"
  value       = aws_acm_certificate.ziti.domain_name
}

# =============================================================================
# Security Groups
# =============================================================================

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

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
  description = "Hint for Ansible SSM inventory configuration"
  value       = <<-EOT
    # Add to your Ansible inventory (aws_ssm.yml):
    # 
    # plugin: amazon.aws.aws_ec2
    # regions:
    #   - us-west-2
    # filters:
    #   tag:Ansible: ziti-${var.environment}
    #   instance-state-name: running
  EOT
}
