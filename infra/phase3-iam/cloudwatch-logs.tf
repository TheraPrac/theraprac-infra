# =============================================================================
# CloudWatch Log Groups for Application Logs
# =============================================================================
# Creates log groups for API and Web applications with retention policies
# to control costs and storage.
#
# Note: Creates log groups for dev, test, and prod environments.
# Dev/Test: 1 day retention (24 hours)
# Prod: 30 days retention

locals {
  # Create log groups for all application environments
  app_environments = ["dev", "test", "prod"]

  # Retention policy: 1 day for dev/test, 30 days for prod
  retention_days = {
    dev  = 1
    test = 1
    prod = 30
  }
}

# API log groups for each environment
resource "aws_cloudwatch_log_group" "api" {
  for_each = toset(local.app_environments)

  name              = "/theraprac/${each.key}/api"
  retention_in_days = local.retention_days[each.key]

  tags = merge(var.common_tags, {
    Name        = "theraprac-${each.key}-api-logs"
    Environment = each.key
    Service     = "api"
  })
}

# Web log groups for each environment
resource "aws_cloudwatch_log_group" "web" {
  for_each = toset(local.app_environments)

  name              = "/theraprac/${each.key}/web"
  retention_in_days = local.retention_days[each.key]

  tags = merge(var.common_tags, {
    Name        = "theraprac-${each.key}-web-logs"
    Environment = each.key
    Service     = "web"
  })
}

