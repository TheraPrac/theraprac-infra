# Phase 5: RDS PostgreSQL

Creates RDS PostgreSQL instances for application databases with Ziti overlay access.

## Status

✅ **Implemented**

## Depends On

- Phase 1 (VPC) - For db subnets
- Phase 3 (IAM) - For KMS encryption key access
- Phase 4 (Ziti) - For internal DNS zone
- Phase 7 (Basic Server) - For edge-router security group

## Prerequisites

Before applying, ensure these AWS resources exist:
- SSM Parameter: `/theraprac/api/{environment}/db-admin-user`
- Secrets Manager: `theraprac/api/{environment}/secrets` with `DB_ADMIN_PASSWORD` key

## Resources Created

### RDS PostgreSQL Instance

- Instance identifier: `db-{environment}-app`
- Engine: PostgreSQL 16.x
- Instance class: `db.t4g.micro` (configurable)
- Storage: 20GB gp3, encrypted at rest
- Multi-AZ: No for non-prod, Yes for prod
- Backup retention: 1 day (non-prod), 7 days (prod)
- TLS/SSL: Required via parameter group

### DB Subnet Group

- Uses db subnets from Phase 1 (az1, az2, az3)
- Non-prod uses `private-db-nonprod-*` subnets
- Prod uses `private-db-prod-*` subnets

### Security Group

- Allows port 5432 only from edge-router security group
- No egress rules (RDS doesn't initiate connections)

### Parameter Group

- PostgreSQL 16 family
- `rds.force_ssl = 1` (TLS required)

## Security

- No public accessibility
- Encrypted at rest (AWS managed key)
- Encrypted in transit (TLS required)
- Credentials sourced from SSM/Secrets Manager
- Access only via Ziti overlay network

## Usage

```bash
# Initialize
terraform init

# Plan for dev environment (edge-router is in nonprod)
terraform plan \
  -var="environment=dev" \
  -var="edge_router_environment=nonprod" \
  -out=tfplan

# Apply
terraform apply tfplan
```

**Important:** The `edge_router_environment` specifies which environment's edge-router
hosts the database service. For dev/test/stage databases, this is typically `nonprod`.
For prod databases, use `prod`.

## Outputs

| Output | Description |
|--------|-------------|
| `db_endpoint` | RDS endpoint (hostname:port) |
| `db_address` | RDS hostname |
| `ziti_service_name` | Suggested Ziti service name |
| `ziti_host_config` | Host config JSON for Ziti |
| `ziti_intercept_config` | Intercept config JSON for Ziti |

## Ziti Service Configuration

After applying Terraform, create the Ziti service using the outputs:

```bash
# Get outputs
terraform output -json

# Use the ziti_host_config and ziti_intercept_config outputs
# to create the Ziti service via Ansible or CLI
```

See `ansible/ziti-db-service/` for automated Ziti configuration.

