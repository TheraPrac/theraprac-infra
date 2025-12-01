# Phase 2: VPC Endpoints

Creates VPC endpoints for AWS services to enable private connectivity.

## Status

📋 **Planned**

## Depends On

- Phase 1 (VPC)

## Planned Endpoints

- **SSM** - Systems Manager for instance management
- **SSM Messages** - Session Manager connectivity
- **EC2 Messages** - EC2 instance communication
- **Secrets Manager** - Secure secrets access
- **S3** - Gateway endpoint for S3 access
- **ECR** - Container registry access (if needed)
- **CloudWatch Logs** - Log shipping

## Notes

VPC endpoints allow private subnets to access AWS services without NAT gateway or internet access.

