# =============================================================================
# TheraPrac Infrastructure - Phase 5: RDS Outputs
# =============================================================================

# =============================================================================
# RDS Instance
# =============================================================================

output "db_instance_id" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "db_endpoint" {
  description = "The connection endpoint (hostname:port)"
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "The database port"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "The name of the database"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "The master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

# =============================================================================
# Network
# =============================================================================

output "db_subnet_group_name" {
  description = "The DB subnet group name"
  value       = aws_db_subnet_group.main.name
}

output "db_security_group_id" {
  description = "The security group ID for the RDS instance"
  value       = aws_security_group.rds.id
}

output "db_availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = aws_db_instance.main.availability_zone
}

# =============================================================================
# Ziti Service Configuration
# =============================================================================
# These outputs help configure the Ziti service for database access

output "ziti_service_name" {
  description = "Suggested Ziti service name for this database"
  value       = "postgres.db.${var.environment}.app.ziti"
}

output "ziti_host_config" {
  description = "Host config JSON for Ziti service"
  value = jsonencode({
    protocol = "tcp"
    address  = aws_db_instance.main.address
    port     = aws_db_instance.main.port
  })
}

output "ziti_intercept_config" {
  description = "Intercept config JSON for Ziti service"
  value = jsonencode({
    protocols  = ["tcp"]
    addresses  = ["postgres.db.${var.environment}.app.ziti"]
    portRanges = [{ low = 5432, high = 5432 }]
  })
}

# =============================================================================
# Connection Strings (for reference)
# =============================================================================

output "connection_info" {
  description = "Database connection information for applications"
  value = {
    host     = "postgres.db.${var.environment}.app.ziti"
    port     = 5432
    database = aws_db_instance.main.db_name
    ssl_mode = "require"
    note     = "Connect via Ziti overlay network"
  }
}



