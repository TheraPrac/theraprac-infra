# =============================================================================
# TheraPrac Infrastructure - Phase 7: Basic Server Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Instance Information
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.basic_server.instance_id
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = module.basic_server.private_ip
}

output "availability_zone" {
  description = "Availability zone of the EC2 instance"
  value       = module.basic_server.availability_zone
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

output "full_name" {
  description = "Full name in dot notation (e.g., app.mt.nonprod)"
  value       = module.basic_server.full_name
}

output "hyphen_name" {
  description = "Hyphenated name (e.g., app-mt-nonprod)"
  value       = module.basic_server.hyphen_name
}

# -----------------------------------------------------------------------------
# DNS
# -----------------------------------------------------------------------------

output "internal_dns" {
  description = "Internal DNS name"
  value       = module.basic_server.internal_dns
}

output "ziti_ssh" {
  description = "Ziti synthetic DNS name for SSH"
  value       = module.basic_server.ziti_ssh
}

# -----------------------------------------------------------------------------
# SSH Commands
# -----------------------------------------------------------------------------

output "ssh_command_ziti" {
  description = "SSH command via Ziti (requires ZDE running)"
  value       = module.basic_server.ssh_command_ziti
}

output "ssh_command_eice" {
  description = "SSH command via EC2 Instance Connect (break-glass)"
  value       = module.basic_server.ssh_command_eice
}

# -----------------------------------------------------------------------------
# For Ansible
# -----------------------------------------------------------------------------

output "ansible_vars" {
  description = "Variables to pass to Ansible playbook"
  value = {
    server_name         = module.basic_server.full_name
    server_internal_dns = module.basic_server.internal_dns
    ziti_ssh_name       = module.basic_server.ziti_ssh
    instance_id         = module.basic_server.instance_id
  }
}

