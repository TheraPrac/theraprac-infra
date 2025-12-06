# =============================================================================
# TheraPrac Infrastructure - Basic Server Module
# =============================================================================
# Creates a private EC2 instance with:
#   - No public IP (private subnet only)
#   - SSH access only from EICE (break-glass)
#   - ziti-edge-tunnel installed for self-hosted Ziti services
#   - ansible + jfinlinson users created via user_data
#   - Private DNS record in theraprac-internal.com
#
# The server runs ziti-edge-tunnel in host mode and self-registers its
# endpoints (e.g., SSH) via the Ziti controller API.
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values - Derived Names
# -----------------------------------------------------------------------------

locals {
  # Naming convention: name.role.environment
  full_name   = "${var.name}.${var.role}.${var.environment}"
  hyphen_name = "${var.name}-${var.role}-${var.environment}"

  # DNS names
  internal_dns = "${local.hyphen_name}.${var.internal_zone_name}"
  ziti_ssh     = "ssh.${local.full_name}.ziti"

  # Tags
  default_tags = {
    Name        = local.hyphen_name
    Role        = "basic-server"
    Tier        = var.tier
    Environment = var.environment
    ZitiSSH     = local.ziti_ssh
    Ansible     = "basic-server"
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Latest Amazon Linux 2023 AMI based on architecture
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-${var.arch}"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = [var.arch]
  }
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
# Use provided security group ID (shared security group from phase7)
# The shared security group and its rules are managed in phase7-basic-server/main.tf

locals {
  security_group_id = var.security_group_id
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [local.security_group_id]
  iam_instance_profile        = var.instance_profile_name
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.default_tags, var.common_tags, {
      Name = "${local.hyphen_name}-root"
    })
  }

  # Create admin users with SSH keys at boot
  # All Ziti installation and configuration is handled by Ansible
  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Log all output for debugging
    exec > >(tee /var/log/user-data.log) 2>&1
    echo "Starting user-data script at $(date)"
    
    # ==========================================================================
    # Create Users
    # ==========================================================================
    
    # Create ansible user for automation
    useradd -m -s /bin/bash ansible
    mkdir -p /home/ansible/.ssh
    echo "${var.ssh_key_ansible}" > /home/ansible/.ssh/authorized_keys
    chown -R ansible:ansible /home/ansible/.ssh
    chmod 700 /home/ansible/.ssh
    chmod 600 /home/ansible/.ssh/authorized_keys
    echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
    chmod 440 /etc/sudoers.d/ansible
    
    # Create jfinlinson user for admin access
    useradd -m -s /bin/bash jfinlinson
    mkdir -p /home/jfinlinson/.ssh
    echo "${var.ssh_key_jfinlinson}" > /home/jfinlinson/.ssh/authorized_keys
    chown -R jfinlinson:jfinlinson /home/jfinlinson/.ssh
    chmod 700 /home/jfinlinson/.ssh
    chmod 600 /home/jfinlinson/.ssh/authorized_keys
    echo "jfinlinson ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/jfinlinson
    chmod 440 /etc/sudoers.d/jfinlinson
    
    # Disable password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart sshd
    
    # ==========================================================================
    # Store Controller Endpoint for Ansible
    # ==========================================================================
    
    mkdir -p /opt/ziti/cfg
    echo "${var.ziti_controller_endpoint}" > /opt/ziti/cfg/controller_endpoint
    chmod 644 /opt/ziti/cfg/controller_endpoint
    
    # ==========================================================================
    # Done
    # ==========================================================================
    
    echo "User-data script completed successfully at $(date)"
    echo "Ziti installation and configuration will be handled by Ansible"
  EOF

  monitoring = false

  tags = merge(local.default_tags, var.common_tags)

  lifecycle {
    ignore_changes = [ami]
  }
}

# -----------------------------------------------------------------------------
# Private DNS Record
# -----------------------------------------------------------------------------

resource "aws_route53_record" "private" {
  zone_id = var.internal_zone_id
  name    = local.internal_dns
  type    = "A"
  ttl     = 300
  records = [aws_instance.server.private_ip]
}


