# Phase 3: IAM Roles & Policies

Creates IAM roles and policies for EC2 instances and services.

## Status

📋 **Planned**

## Depends On

- Phase 1 (VPC)

## Planned Resources

### Instance Profiles

- **App Server Role** - EC2 role for application servers
  - SSM access for management
  - Secrets Manager access for credentials
  - S3 access for assets (if needed)
  - CloudWatch Logs for logging

- **Ziti Router Role** - EC2 role for Ziti edge routers
  - SSM access for management
  - Limited network permissions

### Policies

- Least-privilege policies for each role
- Separate policies for non-prod vs prod where needed

