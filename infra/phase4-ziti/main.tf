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

# -----------------------------------------------------------------------------
# ALB Security Group (ziti-alb-sg)
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "ziti-alb-${var.environment}"
  description = "Security group for Ziti public ALB"
  vpc_id      = local.vpc_id

  tags = {
    Name = "ziti-alb-${var.environment}"
  }
}

# ALB inbound: HTTPS from internet
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "alb-https-inbound" }
}

# ALB outbound: to Ziti EC2 on 443 (HTTPS traffic)
resource "aws_vpc_security_group_egress_rule" "alb_to_ziti_https" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow HTTPS to Ziti instance"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ziti.id

  tags = { Name = "alb-to-ziti-https" }
}

# ALB outbound: to Ziti EC2 on 8080 (health check)
resource "aws_vpc_security_group_egress_rule" "alb_to_ziti_health" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow health check to Ziti instance"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.ziti.id

  tags = { Name = "alb-to-ziti-health" }
}

# -----------------------------------------------------------------------------
# Ziti EC2 Security Group (ziti-ec2-sg)
# -----------------------------------------------------------------------------
resource "aws_security_group" "ziti" {
  name        = "ziti-ec2-${var.environment}"
  description = "Security group for Ziti EC2 instance"
  vpc_id      = local.vpc_id

  tags = {
    Name = "ziti-ec2-${var.environment}"
  }
}

# Ziti inbound: 443 from ALB only
resource "aws_vpc_security_group_ingress_rule" "ziti_https_from_alb" {
  security_group_id            = aws_security_group.ziti.id
  description                  = "Allow HTTPS from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.alb.id

  tags = { Name = "ziti-https-from-alb" }
}

# Ziti inbound: 8080 from ALB only (health check)
resource "aws_vpc_security_group_ingress_rule" "ziti_health_from_alb" {
  security_group_id            = aws_security_group.ziti.id
  description                  = "Allow health check from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb.id

  tags = { Name = "ziti-health-from-alb" }
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

  # NO user_data - Ziti is installed and configured via Ansible
  # See: ansible/ziti-nonprod/playbook.yml

  # Basic monitoring only (detailed monitoring costs extra)
  monitoring = false

  tags = {
    Name    = "ziti-${var.environment}"
    Role    = "ziti-server"
    Ansible = "ziti-${var.environment}"
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
# Application Load Balancer
# =============================================================================

resource "aws_lb" "ziti" {
  name               = "ziti-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "ziti-${var.environment}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "ziti" {
  name        = "ziti-${var.environment}-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    port                = "8080"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "ziti-${var.environment}-tg"
  }
}

# Register EC2 with target group
resource "aws_lb_target_group_attachment" "ziti" {
  target_group_arn = aws_lb_target_group.ziti.arn
  target_id        = aws_instance.ziti.id
  port             = 443
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.ziti.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.ziti.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ziti.arn
  }

  tags = {
    Name = "ziti-${var.environment}-https"
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

