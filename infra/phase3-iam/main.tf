# =============================================================================
# TheraPrac Infrastructure - Phase 3: IAM Roles & Policies
# =============================================================================
# This module creates IAM resources for EC2 instances:
#   - Managed policies for base EC2, Secrets Manager, and Observability
#   - IAM roles for Ziti Controller, Ziti Router, and App Server
#   - Instance profiles for each role
#
# NO SSM permissions are included - all access is via NAT + direct AWS APIs.
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
    key            = "phase3-iam/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "theraprac-terraform-locks"
  }
}

provider "aws" {
  region  = var.aws_region
  # Note: IAM operations require AdministratorAccess (use jfinlinson_admin profile)
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

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Resource naming
  name_prefix = var.project_name

  # ARN patterns for policy restrictions
  secrets_arn_pattern    = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project_name}/${var.environment}/*"
  log_group_arn_pattern  = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/${var.project_name}/${var.environment}/*"
  log_stream_arn_pattern = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/${var.project_name}/${var.environment}/*:log-stream:*"
}

# =============================================================================
# EC2 Assume Role Policy Document (shared by all roles)
# =============================================================================

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# =============================================================================
# Managed Policy: Base EC2 Policy
# =============================================================================
# Minimal permissions common to all EC2 instances

data "aws_iam_policy_document" "base_ec2" {
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "LogsDescribe"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "base_ec2" {
  name        = "TheraPrac-Base-EC2-Policy"
  description = "Base permissions for all TheraPrac EC2 instances"
  policy      = data.aws_iam_policy_document.base_ec2.json

  tags = {
    Name = "TheraPrac-Base-EC2-Policy"
  }
}

# =============================================================================
# Managed Policy: Secrets Manager Read-Only
# =============================================================================
# Scoped to theraprac/nonprod/* secrets only

data "aws_iam_policy_document" "secrets_readonly" {
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      local.secrets_arn_pattern,
      "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:ziti/${var.environment}/*"
    ]
  }
}

resource "aws_iam_policy" "secrets_readonly" {
  name        = "TheraPrac-Secrets-ReadOnly"
  description = "Read-only access to TheraPrac ${var.environment} secrets"
  policy      = data.aws_iam_policy_document.secrets_readonly.json

  tags = {
    Name = "TheraPrac-Secrets-ReadOnly"
  }
}

# =============================================================================
# Managed Policy: Observability Write (CloudWatch Logs + X-Ray)
# =============================================================================
# CloudWatch Logs scoped to /theraprac/nonprod/* log groups
# X-Ray uses * resources (standard practice for trace data)

data "aws_iam_policy_document" "observability_write" {
  # CloudWatch Logs - Create and write to log groups/streams
  statement {
    sid    = "CloudWatchLogsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      local.log_group_arn_pattern,
      local.log_stream_arn_pattern,
    ]
  }

  # X-Ray - Send traces and telemetry
  statement {
    sid    = "XRayWrite"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "observability_write" {
  name        = "TheraPrac-Observability-Write"
  description = "Write access to CloudWatch Logs and X-Ray for TheraPrac ${var.environment}"
  policy      = data.aws_iam_policy_document.observability_write.json

  tags = {
    Name = "TheraPrac-Observability-Write"
  }
}

# =============================================================================
# IAM Role: Ziti Controller
# =============================================================================
# Policies: Base + Observability + Secrets (for bootstrap config)

resource "aws_iam_role" "ziti_controller" {
  name               = "${local.name_prefix}-ziti-controller-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for TheraPrac Ziti Controller EC2 instances"

  tags = {
    Name = "${local.name_prefix}-ziti-controller-role"
  }
}

resource "aws_iam_role_policy_attachment" "ziti_controller_base" {
  role       = aws_iam_role.ziti_controller.name
  policy_arn = aws_iam_policy.base_ec2.arn
}

resource "aws_iam_role_policy_attachment" "ziti_controller_observability" {
  role       = aws_iam_role.ziti_controller.name
  policy_arn = aws_iam_policy.observability_write.arn
}

resource "aws_iam_role_policy_attachment" "ziti_controller_secrets" {
  role       = aws_iam_role.ziti_controller.name
  policy_arn = aws_iam_policy.secrets_readonly.arn
}

resource "aws_iam_instance_profile" "ziti_controller" {
  name = "${local.name_prefix}-ziti-controller-instance-profile"
  role = aws_iam_role.ziti_controller.name

  tags = {
    Name = "${local.name_prefix}-ziti-controller-instance-profile"
  }
}

# =============================================================================
# IAM Role: Ziti Router
# =============================================================================
# Policies: Base + Observability (no secrets needed for routers)

resource "aws_iam_role" "ziti_router" {
  name               = "${local.name_prefix}-ziti-router-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for TheraPrac Ziti Router EC2 instances"

  tags = {
    Name = "${local.name_prefix}-ziti-router-role"
  }
}

resource "aws_iam_role_policy_attachment" "ziti_router_base" {
  role       = aws_iam_role.ziti_router.name
  policy_arn = aws_iam_policy.base_ec2.arn
}

resource "aws_iam_role_policy_attachment" "ziti_router_observability" {
  role       = aws_iam_role.ziti_router.name
  policy_arn = aws_iam_policy.observability_write.arn
}

resource "aws_iam_instance_profile" "ziti_router" {
  name = "${local.name_prefix}-ziti-router-instance-profile"
  role = aws_iam_role.ziti_router.name

  tags = {
    Name = "${local.name_prefix}-ziti-router-instance-profile"
  }
}

# =============================================================================
# IAM Role: App Server (Next.js + Go API)
# =============================================================================
# Policies: Base + Secrets + Observability

resource "aws_iam_role" "app_server" {
  name               = "${local.name_prefix}-app-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for TheraPrac App Server EC2 instances"

  tags = {
    Name = "${local.name_prefix}-app-server-role"
  }
}

resource "aws_iam_role_policy_attachment" "app_server_base" {
  role       = aws_iam_role.app_server.name
  policy_arn = aws_iam_policy.base_ec2.arn
}

resource "aws_iam_role_policy_attachment" "app_server_secrets" {
  role       = aws_iam_role.app_server.name
  policy_arn = aws_iam_policy.secrets_readonly.arn
}

resource "aws_iam_role_policy_attachment" "app_server_observability" {
  role       = aws_iam_role.app_server.name
  policy_arn = aws_iam_policy.observability_write.arn
}

resource "aws_iam_instance_profile" "app_server" {
  name = "${local.name_prefix}-app-server-instance-profile"
  role = aws_iam_role.app_server.name

  tags = {
    Name = "${local.name_prefix}-app-server-instance-profile"
  }
}

