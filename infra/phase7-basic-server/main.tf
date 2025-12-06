# =============================================================================
# TheraPrac Infrastructure - Phase 7: Basic Server
# =============================================================================
# Creates private EC2 instances accessible via Ziti SSH.
# Uses the basic-server module with values from previous phases.
#
# Usage:
#   terraform apply \
#     -var="name=app" \
#     -var="role=mt" \
#     -var="tier=app" \
#     -var="environment=nonprod"
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
    key            = "phase7-basic-server/terraform.tfstate"
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
# Data Sources - Remote State
# =============================================================================

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "theraprac-tfstate-32fcc26f"
    key    = "phase1-vpc/terraform.tfstate"
    region = "us-west-2"
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"
  config = {
    bucket = "theraprac-tfstate-32fcc26f"
    key    = "phase3-iam/terraform.tfstate"
    region = "us-west-2"
  }
}

data "terraform_remote_state" "ziti" {
  backend = "s3"
  config = {
    bucket = "theraprac-tfstate-32fcc26f"
    key    = "phase4-ziti/terraform.tfstate"
    region = "us-west-2"
  }
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Subnet lookup based on tier + environment
  # All basic servers go in az1 for now
  subnet_map = {
    "app.nonprod"  = data.terraform_remote_state.vpc.outputs.private_app_nonprod_subnet_ids_by_az["az1"]
    "app.prod"     = data.terraform_remote_state.vpc.outputs.private_app_prod_subnet_ids_by_az["az1"]
    "db.nonprod"   = data.terraform_remote_state.vpc.outputs.private_db_nonprod_subnet_ids_by_az["az1"]
    "db.prod"      = data.terraform_remote_state.vpc.outputs.private_db_prod_subnet_ids_by_az["az1"]
    "ziti.nonprod" = data.terraform_remote_state.vpc.outputs.private_ziti_nonprod_subnet_ids_by_az["az1"]
    "ziti.prod"    = data.terraform_remote_state.vpc.outputs.private_ziti_prod_subnet_ids_by_az["az1"]
  }

  subnet_id = local.subnet_map["${var.tier}.${var.environment}"]
}

# =============================================================================
# Shared Security Group for Basic Servers
# =============================================================================
# All basic servers share the same security group rules:
#   - SSH from EICE (break-glass access)
#   - All outbound traffic
# =============================================================================

resource "aws_security_group" "basic_servers" {
  name        = "shared-basic-servers-${var.environment}"
  description = "Shared security group for all basic servers in ${var.environment}. Rules: SSH from EICE, all outbound."
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  tags = merge(var.common_tags, {
    Name        = "shared-basic-servers-${var.environment}-sg"
    Environment = var.environment
    Purpose     = "shared-basic-server-sg"
  })
}

# Inbound: SSH from EC2 Instance Connect Endpoint (break-glass access)
resource "aws_vpc_security_group_ingress_rule" "ssh_from_eice" {
  security_group_id            = aws_security_group.basic_servers.id
  description                  = "Allow SSH from EC2 Instance Connect Endpoint"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = data.terraform_remote_state.ziti.outputs.eice_security_group_id

  tags = {
    Name = "shared-basic-servers-ssh-from-eice-${var.environment}"
  }
}

# Outbound: All traffic (for package updates, SSM, Ziti enrollment, etc.)
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.basic_servers.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "shared-basic-servers-all-outbound-${var.environment}"
  }
}

# =============================================================================
# Basic Server Module
# =============================================================================

module "basic_server" {
  source = "../modules/basic-server"

  # Identity
  name        = var.name
  role        = var.role
  tier        = var.tier
  environment = var.environment

  # Instance config
  instance_type = var.instance_type
  arch          = var.arch

  # SSH keys
  ssh_key_ansible    = var.ssh_key_ansible
  ssh_key_jfinlinson = var.ssh_key_jfinlinson

  # Network (from remote state)
  vpc_id                 = data.terraform_remote_state.vpc.outputs.vpc_id
  vpc_cidr               = data.terraform_remote_state.vpc.outputs.vpc_cidr_block
  subnet_id              = local.subnet_id
  internal_zone_id       = data.terraform_remote_state.ziti.outputs.internal_zone_id
  internal_zone_name     = data.terraform_remote_state.ziti.outputs.internal_zone_name
  
  # Use shared security group instead of creating one per server
  security_group_id = aws_security_group.basic_servers.id

  # Ziti controller for tunneler registration
  ziti_controller_endpoint = data.terraform_remote_state.ziti.outputs.ziti_public_url

  # IAM
  instance_profile_name = data.terraform_remote_state.iam.outputs.app_server_instance_profile_name

  # Tags
  common_tags = var.common_tags
}


