# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# =============================================================================
# Public Subnet Outputs
# =============================================================================

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "public_subnet_ids_by_az" {
  description = "Map of AZ alias to public subnet ID"
  value       = { for k, subnet in aws_subnet.public : k => subnet.id }
}

# =============================================================================
# Non-Prod Subnet Outputs
# =============================================================================

output "private_app_nonprod_subnet_ids" {
  description = "List of non-prod app subnet IDs"
  value       = [for subnet in aws_subnet.private_app_nonprod : subnet.id]
}

output "private_app_nonprod_subnet_ids_by_az" {
  description = "Map of AZ alias to non-prod app subnet ID"
  value       = { for k, subnet in aws_subnet.private_app_nonprod : k => subnet.id }
}

output "private_db_nonprod_subnet_ids" {
  description = "List of non-prod database subnet IDs"
  value       = [for subnet in aws_subnet.private_db_nonprod : subnet.id]
}

output "private_db_nonprod_subnet_ids_by_az" {
  description = "Map of AZ alias to non-prod database subnet ID"
  value       = { for k, subnet in aws_subnet.private_db_nonprod : k => subnet.id }
}

output "private_ziti_nonprod_subnet_ids" {
  description = "List of non-prod Ziti subnet IDs"
  value       = [for subnet in aws_subnet.private_ziti_nonprod : subnet.id]
}

output "private_ziti_nonprod_subnet_ids_by_az" {
  description = "Map of AZ alias to non-prod Ziti subnet ID"
  value       = { for k, subnet in aws_subnet.private_ziti_nonprod : k => subnet.id }
}

# =============================================================================
# Prod Subnet Outputs
# =============================================================================

output "private_app_prod_subnet_ids" {
  description = "List of prod app subnet IDs"
  value       = [for subnet in aws_subnet.private_app_prod : subnet.id]
}

output "private_app_prod_subnet_ids_by_az" {
  description = "Map of AZ alias to prod app subnet ID"
  value       = { for k, subnet in aws_subnet.private_app_prod : k => subnet.id }
}

output "private_db_prod_subnet_ids" {
  description = "List of prod database subnet IDs"
  value       = [for subnet in aws_subnet.private_db_prod : subnet.id]
}

output "private_db_prod_subnet_ids_by_az" {
  description = "Map of AZ alias to prod database subnet ID"
  value       = { for k, subnet in aws_subnet.private_db_prod : k => subnet.id }
}

output "private_ziti_prod_subnet_ids" {
  description = "List of prod Ziti subnet IDs"
  value       = [for subnet in aws_subnet.private_ziti_prod : subnet.id]
}

output "private_ziti_prod_subnet_ids_by_az" {
  description = "Map of AZ alias to prod Ziti subnet ID"
  value       = { for k, subnet in aws_subnet.private_ziti_prod : k => subnet.id }
}

# =============================================================================
# Route Table Outputs
# =============================================================================

output "route_table_ids" {
  description = "Map of route table names to IDs"
  value = {
    public       = aws_route_table.public.id
    app_nonprod  = aws_route_table.private_app_nonprod.id
    db_nonprod   = aws_route_table.private_db_nonprod.id
    ziti_nonprod = aws_route_table.private_ziti_nonprod.id
    app_prod     = aws_route_table.private_app_prod.id
    db_prod      = aws_route_table.private_db_prod.id
    ziti_prod    = aws_route_table.private_ziti_prod.id
  }
}

