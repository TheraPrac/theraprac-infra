# Phase 6: Application Infrastructure

Deploys EC2 instances and supporting resources for the TheraPrac application.

## Status

📋 **Planned**

## Depends On

- Phase 1 (VPC)
- Phase 2 (VPC Endpoints)
- Phase 3 (IAM)
- Phase 4 (Ziti) - for zero-trust access
- Phase 5 (RDS) - for database connectivity

## Planned Resources

### Non-Prod Environment

- EC2 instance(s) for API server
- Security groups for application traffic
- Ziti service configuration

### Prod Environment

- EC2 instance(s) for API server (potentially ASG)
- Application Load Balancer (if needed)
- Security groups for production traffic
- Ziti service configuration

### Shared Resources

- AMI management (Amazon Linux 2023 or Ubuntu)
- Launch templates
- CloudWatch alarms and dashboards

## Ansible Integration

This phase will include Ansible playbooks for:

- Base OS configuration
- Application deployment
- Service configuration
- Monitoring agent installation
- Log shipping setup

## Access Pattern

All application access will flow through Ziti:

```
Client → Ziti SDK → Ziti Edge Router → App Server → RDS
```

No direct internet exposure for application servers.

