# Phase 5: RDS PostgreSQL

Creates RDS PostgreSQL instances for application databases.

## Status

📋 **Planned**

## Depends On

- Phase 1 (VPC)
- Phase 3 (IAM)

## Planned Resources

### Non-Prod Database

- RDS PostgreSQL instance (db.t3.micro or small)
- Multi-AZ: No (cost savings for non-prod)
- Subnet group using non-prod DB subnets
- Security group for app server access

### Prod Database

- RDS PostgreSQL instance (appropriately sized)
- Multi-AZ: Yes (high availability)
- Subnet group using prod DB subnets
- Security group for prod app server access
- Automated backups with retention
- Performance Insights enabled

### Shared Resources

- DB subnet groups
- Parameter groups
- Option groups (if needed)

## Security

- No public accessibility
- Encrypted at rest (KMS)
- Encrypted in transit (SSL)
- Credentials stored in Secrets Manager

