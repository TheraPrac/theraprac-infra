# =============================================================================
# TheraPrac Infrastructure - Basic Server Module
# =============================================================================
# Creates a private EC2 instance with:
#   - No public IP (private subnet only)
#   - SSH access only from EICE and Ziti router
#   - ansible + jfinlinson users created via user_data
#   - Private DNS record in theraprac-internal.com
#
# Access is via Ziti SSH (primary) or EC2 Instance Connect (break-glass).
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

resource "aws_security_group" "server" {
  name        = "basic-server-${local.hyphen_name}"
  description = "Security group for basic server ${local.full_name}"
  vpc_id      = var.vpc_id

  tags = merge(local.default_tags, var.common_tags, {
    Name = "basic-server-${local.hyphen_name}-sg"
  })
}

# Inbound: SSH from EC2 Instance Connect Endpoint
resource "aws_vpc_security_group_ingress_rule" "ssh_from_eice" {
  security_group_id            = aws_security_group.server.id
  description                  = "Allow SSH from EC2 Instance Connect Endpoint"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.eice_security_group_id

  tags = { Name = "${local.hyphen_name}-ssh-from-eice" }
}

# Inbound: SSH from Ziti subnet (router needs to reach this server)
resource "aws_vpc_security_group_ingress_rule" "ssh_from_ziti" {
  security_group_id = aws_security_group.server.id
  description       = "Allow SSH from Ziti router subnet"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ziti_subnet_cidr

  tags = { Name = "${local.hyphen_name}-ssh-from-ziti" }
}

# Outbound: All traffic (for package updates, SSM, etc.)
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.server.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${local.hyphen_name}-all-outbound" }
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.server.id]
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
  user_data = <<-EOF
    #!/bin/bash
    set -e
    
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

