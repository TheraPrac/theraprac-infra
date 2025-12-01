# TheraPrac Infrastructure

AWS infrastructure deployment for TheraPrac using Terraform and Ansible.

## Phases

| Phase | Directory | Description | Status |
|-------|-----------|-------------|--------|
| 1 | `infra/phase1-vpc` | VPC, Subnets, Route Tables | ✅ Ready |
| 2 | `infra/phase2-endpoints` | VPC Endpoints | 📋 Planned |
| 3 | `infra/phase3-iam` | IAM Roles & Policies | 📋 Planned |
| 4 | `infra/phase4-ziti` | Ziti Network Infrastructure | 📋 Planned |
| 5 | `infra/phase5-rds` | RDS PostgreSQL | 📋 Planned |
| 6 | `infra/phase6-app` | Application Infrastructure | 📋 Planned |

## Prerequisites

- Terraform >= 1.6.0
- AWS CLI configured with profile `jfinlinson_cli`
- AWS account access to us-west-2

## Quick Start

```bash
cd infra/phase1-vpc
terraform init
terraform plan
terraform apply
```

## State Management

Phase 1 uses local state. After bootstrap module is applied, migrate to S3 backend.

See `infra/modules/bootstrap/` for state bucket setup.

## Directory Structure

```
theraprac-infra/
├── README.md
├── infra/
│   ├── phase1-vpc/          # VPC & network foundation
│   ├── phase2-endpoints/    # VPC endpoints
│   ├── phase3-iam/          # IAM roles & policies
│   ├── phase4-ziti/         # Ziti zero-trust network
│   ├── phase5-rds/          # RDS PostgreSQL
│   ├── phase6-app/          # Application infrastructure
│   └── modules/             # Shared Terraform modules
│       └── bootstrap/       # State bucket & DynamoDB
```

