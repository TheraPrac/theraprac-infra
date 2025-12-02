# =============================================================================
# TheraPrac Infrastructure - Phase 4: Ziti Controller + Router
# =============================================================================
# This module deploys:
#   - EC2 instance running Ziti controller + router (combined)
#   - Application Load Balancer for public HTTPS access
#   - ACM certificate with DNS validation
#   - Route53 DNS record
#   - Security groups with least-privilege access
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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

# Remote state from Phase 2 (NAT instance)
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

# Route53 hosted zone
data "aws_route53_zone" "main" {
  name         = var.route53_zone_name
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
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id

  # Subnet IDs
  ziti_subnet_id = data.terraform_remote_state.vpc.outputs.private_ziti_nonprod_subnet_ids_by_az["az1"]
  public_subnet_ids = [
    data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az1"],
    data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az2"],
    data.terraform_remote_state.vpc.outputs.public_subnet_ids_by_az["az3"],
  ]

  # NAT instance security group for outbound rules
  nat_security_group_id = data.terraform_remote_state.nat.outputs.nat_security_group_id

  # IAM instance profile
  ziti_instance_profile = data.terraform_remote_state.iam.outputs.ziti_controller_instance_profile_name
}

# =============================================================================
# ACM Certificate
# =============================================================================

resource "aws_acm_certificate" "ziti" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = "ziti-${var.environment}-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record
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
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "ziti" {
  certificate_arn         = aws_acm_certificate.ziti.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# =============================================================================
# Security Groups
# =============================================================================

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "ziti-alb-${var.environment}"
  description = "Security group for Ziti ALB"
  vpc_id      = local.vpc_id

  tags = {
    Name = "ziti-alb-${var.environment}"
  }
}

# ALB inbound from internet on 443
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "alb-https-inbound" }
}

# ALB outbound to Ziti instance (HTTPS traffic)
resource "aws_vpc_security_group_egress_rule" "alb_to_ziti" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow HTTPS to Ziti instance"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ziti.id

  tags = { Name = "alb-to-ziti" }
}

# ALB outbound to Ziti instance (health check traffic)
resource "aws_vpc_security_group_egress_rule" "alb_to_ziti_healthcheck" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow health check to Ziti instance"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.ziti.id

  tags = { Name = "alb-to-ziti-healthcheck" }
}

# Ziti EC2 Security Group
resource "aws_security_group" "ziti" {
  name        = "ziti-instance-${var.environment}"
  description = "Security group for Ziti EC2 instance"
  vpc_id      = local.vpc_id

  tags = {
    Name = "ziti-instance-${var.environment}"
  }
}

# Ziti inbound from ALB on 443
resource "aws_vpc_security_group_ingress_rule" "ziti_from_alb" {
  security_group_id            = aws_security_group.ziti.id
  description                  = "Allow HTTPS from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.alb.id

  tags = { Name = "ziti-from-alb" }
}

# Ziti inbound from ALB on 8080 for health checks
resource "aws_vpc_security_group_ingress_rule" "ziti_healthcheck_from_alb" {
  security_group_id            = aws_security_group.ziti.id
  description                  = "Allow health check from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb.id

  tags = { Name = "ziti-healthcheck-from-alb" }
}

# Ziti inbound from VPC for internal Ziti traffic (controller API, router links)
resource "aws_vpc_security_group_ingress_rule" "ziti_from_vpc" {
  security_group_id = aws_security_group.ziti.id
  description       = "Allow Ziti traffic from VPC"
  ip_protocol       = "tcp"
  from_port         = 6262
  to_port           = 6262
  cidr_ipv4         = var.vpc_cidr

  tags = { Name = "ziti-internal" }
}

# Ziti outbound to VPC (for internal services)
resource "aws_vpc_security_group_egress_rule" "ziti_to_vpc" {
  security_group_id = aws_security_group.ziti.id
  description       = "Allow all to VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr

  tags = { Name = "ziti-to-vpc" }
}

# Ziti outbound to internet via NAT (for AWS APIs, package downloads)
resource "aws_vpc_security_group_egress_rule" "ziti_to_internet" {
  security_group_id = aws_security_group.ziti.id
  description       = "Allow HTTPS to internet via NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "ziti-to-internet" }
}

# =============================================================================
# EC2 Instance
# =============================================================================

resource "aws_instance" "ziti" {
  ami                    = data.aws_ami.amazon_linux_2023_arm.id
  instance_type          = var.instance_type
  subnet_id              = local.ziti_subnet_id
  iam_instance_profile   = local.ziti_instance_profile
  vpc_security_group_ids = [aws_security_group.ziti.id]

  # No public IP - private subnet with NAT
  associate_public_ip_address = false

  # Root volume (AL2023 requires minimum 30GB)
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "ziti-${var.environment}-root"
    }
  }

  # Bootstrap via cloud-init, configure via Ansible (hybrid approach)
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    github_repo   = var.github_repo
    github_branch = var.github_branch
    ansible_dir   = var.ansible_dir
    environment   = var.environment
  })

  tags = {
    Name    = "ziti-${var.environment}"
    Role    = "ziti-controller-router"
  }

  lifecycle {
    # User data changes require instance replacement to take effect
    replace_triggered_by = [null_resource.user_data_trigger]
  }
}

# Track user_data changes to trigger instance replacement
resource "null_resource" "user_data_trigger" {
  triggers = {
    user_data_hash = sha256(templatefile("${path.module}/user-data.sh.tftpl", {
      github_repo   = var.github_repo
      github_branch = var.github_branch
      ansible_dir   = var.ansible_dir
      environment   = var.environment
    }))
  }
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
    path                = "/health"
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
# Route53 DNS Record
# =============================================================================

resource "aws_route53_record" "ziti" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
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

