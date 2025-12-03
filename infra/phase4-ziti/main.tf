# =============================================================================
# TheraPrac Infrastructure - Phase 4: Ziti Server Infrastructure
# =============================================================================
# This module deploys INFRASTRUCTURE ONLY for the Ziti controller + router:
#   - EC2 instance (plain OS, no software installation)
#   - Application Load Balancer for public HTTPS access
#   - ACM certificate with DNS validation
#   - Route53 public DNS record (ziti-nonprod.theraprac.com)
#   - Route53 private hosted zone (theraprac-internal.com)
#   - Route53 private DNS record (ziti-instance-nonprod.theraprac-internal.com)
#   - Security groups with least-privilege access
#   - EC2 Instance Connect Endpoint for SSH access
#
# IMPORTANT: Ziti software installation and configuration is handled by
# Ansible, NOT Terraform. See ansible/ziti-nonprod/ for the playbook.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "theraprac-tfstate-32fcc26f"
    key            = "phase4-ziti/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "theraprac-terraform-locks"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = merge(var.common_tags, {
      Environment = var.environment
    })
  }
}

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

# Remote state from Phase 1 (VPC)
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "theraprac-tfstate-32fcc26f"
    key    = "phase1-vpc/terraform.tfstate"
    region = "us-west-2"
  }
}

# Remote state from Phase 2 (NAT Gateway)
data "terraform_remote_state" "nat" {
  backend = "s3"
  config = {
    bucket = "theraprac-tfstate-32fcc26f"
    key    = "phase2-endpoints/terraform.tfstate"
    region = "us-west-2"
  }
}

# Remote state from Phase 3 (IAM)
data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "theraprac-tfstate-32fcc26f"
    key    = "phase3-iam/terraform.tfstate"
    region = "us-west-2"
  }
}

# Route53 public hosted zone (theraprac.com)
data "aws_route53_zone" "public" {
  name         = var.route53_public_zone_name
  private_zone = false
}

# Latest Amazon Linux 2023 ARM64 AMI (supported until 2028)
data "aws_ami" "amazon_linux_2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  vpc_id   = data.terraform_remote_state.vpc.outputs.vpc_id
  vpc_cidr = data.terraform_remote_state.vpc.outputs.vpc_cidr_block

  # Subnet IDs
  ziti_subnet_id = data.terraform_remote_state.vpc.outputs.private_ziti_nonprod_subnet_ids_by_az["az1"]
  public_subnet_ids = [
    data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az1"],
    data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az2"],
    data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az3"],
  ]

  # IAM instance profile (created in Phase 3)
  ziti_instance_profile = data.terraform_remote_state.iam.outputs.ziti_controller_instance_profile_name
}

# =============================================================================
# Private Hosted Zone (theraprac-internal.com)
# =============================================================================
# This private zone is used for internal service discovery within the VPC.
# Only resources within the associated VPC can resolve these DNS names.

resource "aws_route53_zone" "private" {
  name    = var.route53_private_zone_name
  comment = "Private hosted zone for TheraPrac internal services"

  vpc {
    vpc_id = local.vpc_id
  }

  tags = {
    Name = "theraprac-internal"
  }
}

# =============================================================================
# FUTURE DNS RECORDS (to be created in later phases)
# =============================================================================
# 
# App Server (Phase 5 - shared Next.js + Go API instance):
#   Name: app-nonprod.theraprac-internal.com
#   Type: A
#   Target: app nonprod EC2 private IP
#
# Database (Phase 6 - RDS):
#   Name: db-nonprod.theraprac-internal.com
#   Type: CNAME
#   Target: RDS endpoint (e.g., theraprac-nonprod.xxxxx.us-west-2.rds.amazonaws.com)
#
# =============================================================================

# =============================================================================
# ACM Certificate
# =============================================================================

resource "aws_acm_certificate" "ziti" {
  domain_name       = var.ziti_public_domain
  validation_method = "DNS"

  tags = {
    Name = "ziti-${var.environment}-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record in public zone
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ziti.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.public.zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "ziti" {
  certificate_arn         = aws_acm_certificate.ziti.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# =============================================================================
# Security Groups
# =============================================================================
# NOTE: NLB does not use security groups. Traffic filtering happens at the
# target (EC2 instance) level. The EC2 security group must allow:
#   - Port 443 from 0.0.0.0/0 (NLB forwards client IPs or uses its own)
#   - Port 8080 from VPC CIDR (NLB health checks come from within VPC)
# =============================================================================

# -----------------------------------------------------------------------------
# Ziti EC2 Security Group (ziti-ec2-sg)
# -----------------------------------------------------------------------------
resource "aws_security_group" "ziti" {
  name        = "ziti-instance-${var.environment}"
  description = "Security group for Ziti EC2 instance"
  vpc_id      = local.vpc_id

  tags = {
    Name = "ziti-instance-${var.environment}"
  }
}

# Ziti inbound: 443 from anywhere (NLB TCP passthrough preserves client IP)
resource "aws_vpc_security_group_ingress_rule" "ziti_https_from_nlb" {
  security_group_id = aws_security_group.ziti.id
  description       = "Allow HTTPS via NLB (TCP passthrough)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "ziti-https-from-nlb" }
}

# Ziti inbound: 8442 from anywhere (Router edge listener for SDK/tunnel data)
resource "aws_vpc_security_group_ingress_rule" "ziti_router_edge_from_nlb" {
  security_group_id = aws_security_group.ziti.id
  description       = "Allow router edge port via NLB (TCP passthrough)"
  ip_protocol       = "tcp"
  from_port         = 8442
  to_port           = 8442
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "ziti-router-edge-from-nlb" }
}

# Ziti inbound: 8080 from VPC (NLB health checks)
resource "aws_vpc_security_group_ingress_rule" "ziti_health_from_nlb" {
  security_group_id = aws_security_group.ziti.id
  description       = "Allow health check from NLB"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = local.vpc_cidr

  tags = { Name = "ziti-health-from-nlb" }
}

# Ziti outbound: all traffic to 0.0.0.0/0 via NAT Gateway
# Required for: package updates, Ziti binary downloads, AWS API calls
resource "aws_vpc_security_group_egress_rule" "ziti_to_internet" {
  security_group_id = aws_security_group.ziti.id
  description       = "Allow all outbound via NAT Gateway"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "ziti-to-internet" }
}

# =============================================================================
# EC2 Instance (Plain OS - Ziti installed via Ansible)
# =============================================================================

resource "aws_instance" "ziti" {
  # Amazon Linux 2023 ARM64 (Graviton) - supported until 2028
  ami           = data.aws_ami.amazon_linux_2023_arm.id
  instance_type = var.instance_type

  # Network configuration
  subnet_id                   = local.ziti_subnet_id
  vpc_security_group_ids      = [aws_security_group.ziti.id]
  associate_public_ip_address = false

  # IAM role for Secrets Manager, CloudWatch, etc.
  iam_instance_profile = local.ziti_instance_profile

  # Root volume
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "ziti-${var.environment}-root"
    }
  }

  # Create admin users with SSH keys at boot
  # Ziti software is installed and configured via Ansible after boot
  # SSH keys are passed via variables (marked sensitive) to avoid state exposure
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
  EOF

  # Basic monitoring only (detailed monitoring costs extra)
  monitoring = false

  tags = {
    Name        = "ziti-${var.environment}"
    Role        = "ziti-server"
    Ansible     = "ziti-${var.environment}"
    ZitiSSH     = "ssh.ziti-${var.environment}.ziti"
    Environment = var.environment
  }
}

# Private DNS record for Ziti EC2 instance
resource "aws_route53_record" "ziti_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "ziti-instance-${var.environment}.${var.route53_private_zone_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.ziti.private_ip]
}

# =============================================================================
# Network Load Balancer (TCP Passthrough)
# =============================================================================
# IMPORTANT: We use NLB with TCP passthrough instead of ALB with HTTPS termination.
# This is REQUIRED for Ziti enrollment to work correctly because:
#   1. The router connects to the controller URL and fetches the TLS server cert
#   2. The router uses that cert's public key to verify the enrollment JWT
#   3. If ALB terminates TLS, the router gets the ACM cert (wrong key!)
#   4. With NLB TCP passthrough, the controller presents its own TLS cert directly
# =============================================================================

resource "aws_lb" "ziti" {
  name               = "ziti-${var.environment}"
  internal           = false
  load_balancer_type = "network"
  subnets            = local.public_subnet_ids

  # NLB doesn't use security groups - traffic filtering happens at target level
  enable_deletion_protection = false

  tags = {
    Name = "ziti-${var.environment}-nlb"
  }
}

# Target Group (TCP passthrough to port 443)
# NOTE: Using name_prefix to allow seamless replacement
resource "aws_lb_target_group" "ziti" {
  name_prefix = "ziti-"
  port        = 443
  protocol    = "TCP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  # NLB health check - TCP to port 8080 (healthcheck endpoint)
  health_check {
    enabled             = true
    port                = "8080"
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = {
    Name = "ziti-${var.environment}-tcp-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Register EC2 with target group
resource "aws_lb_target_group_attachment" "ziti" {
  target_group_arn = aws_lb_target_group.ziti.arn
  target_id        = aws_instance.ziti.id
  port             = 443
}

# TCP Listener for Controller (port 443 - passthrough, no TLS termination)
resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.ziti.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ziti.arn
  }

  tags = {
    Name = "ziti-${var.environment}-tcp"
  }
}

# =============================================================================
# Router Edge Port (8442) - For SDK/Tunnel Data Connections
# =============================================================================
# ZDE (Ziti Desktop Edge) connects to the controller (443) for enrollment and
# service discovery, but actual data traffic flows through the router (8442).
# Without exposing port 8442, ZDE can see services but cannot send data.
# =============================================================================

# Target Group for Router Edge (TCP passthrough to port 8442)
resource "aws_lb_target_group" "ziti_router" {
  name_prefix = "zrtr-"
  port        = 8442
  protocol    = "TCP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    port                = "8442"
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
  }

  tags = {
    Name = "ziti-router-${var.environment}-tcp-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Register EC2 with router target group
resource "aws_lb_target_group_attachment" "ziti_router" {
  target_group_arn = aws_lb_target_group.ziti_router.arn
  target_id        = aws_instance.ziti.id
  port             = 8442
}

# TCP Listener for Router Edge (port 8442 - passthrough)
resource "aws_lb_listener" "router_edge" {
  load_balancer_arn = aws_lb.ziti.arn
  port              = "8442"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ziti_router.arn
  }

  tags = {
    Name = "ziti-router-${var.environment}-tcp"
  }
}

# =============================================================================
# Route53 Public DNS Record
# =============================================================================

resource "aws_route53_record" "ziti_public" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.ziti_public_domain
  type    = "A"

  alias {
    name                   = aws_lb.ziti.dns_name
    zone_id                = aws_lb.ziti.zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# EC2 Instance Connect Endpoint (for SSH access to private instances)
# =============================================================================

resource "aws_security_group" "eice" {
  name        = "ec2-instance-connect-endpoint-${var.environment}"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = local.vpc_id

  tags = {
    Name = "eice-${var.environment}"
  }
}

# EICE outbound to Ziti instance on SSH
resource "aws_vpc_security_group_egress_rule" "eice_to_ziti" {
  security_group_id            = aws_security_group.eice.id
  description                  = "Allow SSH to Ziti instance"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.ziti.id

  tags = { Name = "eice-to-ziti-ssh" }
}

# Ziti instance inbound from EICE
resource "aws_vpc_security_group_ingress_rule" "ziti_from_eice" {
  security_group_id            = aws_security_group.ziti.id
  description                  = "Allow SSH from EC2 Instance Connect Endpoint"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.eice.id

  tags = { Name = "ziti-from-eice-ssh" }
}

resource "aws_ec2_instance_connect_endpoint" "main" {
  subnet_id          = local.ziti_subnet_id
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false

  tags = {
    Name = "eice-${var.environment}"
  }
}

