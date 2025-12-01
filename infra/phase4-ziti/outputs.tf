# =============================================================================
# TheraPrac Infrastructure - Phase 4: Ziti Outputs
# =============================================================================

# =============================================================================
# EC2 Instance
# =============================================================================

output "ziti_instance_id" {
  description = "ID of the Ziti EC2 instance"
  value       = aws_instance.ziti.id
}

output "ziti_instance_private_ip" {
  description = "Private IP of the Ziti EC2 instance"
  value       = aws_instance.ziti.private_ip
}

output "ziti_instance_private_dns" {
  description = "Private DNS of the Ziti EC2 instance"
  value       = aws_instance.ziti.private_dns
}

# =============================================================================
# Load Balancer
# =============================================================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.ziti.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.ziti.arn
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.ziti.zone_id
}

# =============================================================================
# DNS
# =============================================================================

output "route53_record_name" {
  description = "Route53 record name for Ziti"
  value       = aws_route53_record.ziti.name
}

output "route53_record_fqdn" {
  description = "Fully qualified domain name for Ziti"
  value       = aws_route53_record.ziti.fqdn
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
# Connection Info
# =============================================================================

output "ziti_url" {
  description = "Public URL to access Ziti controller"
  value       = "https://${var.domain_name}"
}

output "ansible_inventory_entry" {
  description = "Ansible inventory entry for this host"
  value       = <<-EOT
    [ziti_nonprod]
    ${aws_instance.ziti.private_ip} ansible_host=${aws_instance.ziti.private_ip}
  EOT
}

