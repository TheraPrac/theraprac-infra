# =============================================================================
# TheraPrac Infrastructure - Phase 5: RDS PostgreSQL
# =============================================================================
# Creates RDS PostgreSQL instance for application databases.
# Access is restricted to edge-router via Ziti overlay network.
#
# Usage:
#   terraform plan -out=tfplan
#   terraform apply tfplan
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
    key            = "phase5-rds/terraform.tfstate"
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
# Data Sources - Credentials from SSM/Secrets Manager
# =============================================================================

# Master username from SSM Parameter Store
data "aws_ssm_parameter" "db_admin_user" {
  name = "/theraprac/api/${var.environment}/db-admin-user"
}

# Master password from Secrets Manager
data "aws_secretsmanager_secret" "api_secrets" {
  name = "theraprac/api/${var.environment}/secrets"
}

data "aws_secretsmanager_secret_version" "api_secrets" {
  secret_id = data.aws_secretsmanager_secret.api_secrets.id
}

# =============================================================================
# Data Sources - Edge Router Security Group
# =============================================================================
# The edge-router uses the shared-basic-servers security group from phase7.
# We look it up by name since phase7 uses workspaces.
# Note: Edge router environment may differ from database environment
# (e.g., edge-router is nonprod but serves dev/test/stage databases)

data "aws_security_group" "edge_router" {
  name   = "shared-basic-servers-${var.edge_router_environment}"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Parse secrets JSON for DB admin password
  api_secrets       = jsondecode(data.aws_secretsmanager_secret_version.api_secrets.secret_string)
  db_admin_user     = data.aws_ssm_parameter.db_admin_user.value
  db_admin_password = local.api_secrets["DB_ADMIN_PASSWORD"]

  # Naming
  db_identifier = "db-${var.environment}-app"

  # Subnet IDs for DB subnet group (all 3 AZs)
  db_subnet_ids = var.environment == "prod" ? [
    data.terraform_remote_state.vpc.outputs.private_db_prod_subnet_ids_by_az["az1"],
    data.terraform_remote_state.vpc.outputs.private_db_prod_subnet_ids_by_az["az2"],
    data.terraform_remote_state.vpc.outputs.private_db_prod_subnet_ids_by_az["az3"],
    ] : [
    data.terraform_remote_state.vpc.outputs.private_db_nonprod_subnet_ids_by_az["az1"],
    data.terraform_remote_state.vpc.outputs.private_db_nonprod_subnet_ids_by_az["az2"],
    data.terraform_remote_state.vpc.outputs.private_db_nonprod_subnet_ids_by_az["az3"],
  ]
}

# =============================================================================
# DB Subnet Group
# =============================================================================

resource "aws_db_subnet_group" "main" {
  name        = "theraprac-db-${var.environment}"
  description = "DB subnet group for TheraPrac ${var.environment} databases"
  subnet_ids  = local.db_subnet_ids

  tags = merge(var.common_tags, {
    Name        = "theraprac-db-${var.environment}"
    Environment = var.environment
  })
}

# =============================================================================
# Security Group for RDS
# =============================================================================
# Only allows access from the edge-router security group on port 5432

resource "aws_security_group" "rds" {
  name        = "rds-${var.environment}"
  description = "Security group for RDS PostgreSQL. Access only from edge-router on port 5432."
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  tags = merge(var.common_tags, {
    Name        = "rds-${var.environment}-sg"
    Environment = var.environment
    Purpose     = "rds-postgresql"
  })
}

# Inbound: PostgreSQL from edge-router security group only
resource "aws_vpc_security_group_ingress_rule" "postgres_from_edge_router" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Allow PostgreSQL from edge-router"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = data.aws_security_group.edge_router.id

  tags = {
    Name = "rds-postgres-from-edge-router-${var.environment}"
  }
}

# No egress rules - RDS doesn't initiate outbound connections

# =============================================================================
# DB Parameter Group (Force SSL)
# =============================================================================

resource "aws_db_parameter_group" "postgres16" {
  name        = "theraprac-postgres16-${var.environment}"
  family      = "postgres16"
  description = "TheraPrac PostgreSQL 16 parameter group with SSL enforced"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = merge(var.common_tags, {
    Name        = "theraprac-postgres16-${var.environment}"
    Environment = var.environment
  })
}

# =============================================================================
# RDS PostgreSQL Instance
# =============================================================================

resource "aws_db_instance" "main" {
  identifier = local.db_identifier

  # Engine
  engine               = "postgres"
  engine_version       = "16.11"
  instance_class       = var.instance_class
  parameter_group_name = aws_db_parameter_group.postgres16.name

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = local.db_admin_user
  password = local.db_admin_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 5432

  # Availability
  multi_az          = var.multi_az
  availability_zone = var.multi_az ? null : var.availability_zone

  # Backup
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Monitoring
  performance_insights_enabled = var.performance_insights_enabled

  # Deletion protection (enabled for prod)
  deletion_protection       = var.environment == "prod"
  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.db_identifier}-final-snapshot" : null

  # Apply changes immediately in non-prod
  apply_immediately = var.environment != "prod"

  tags = merge(var.common_tags, {
    Name        = local.db_identifier
    Environment = var.environment
    Purpose     = "application-database"
  })

  lifecycle {
    ignore_changes = [
      password, # Don't recreate if password changes externally
    ]
  }
}

