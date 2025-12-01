# TheraPrac Infrastructure

AWS infrastructure deployment for TheraPrac using Terraform and Ansible.

## Phases

| Phase | Directory | Description | Status |
|-------|-----------|-------------|--------|
| 0 | `infra/phase0-bootstrap` | S3 + DynamoDB for Terraform state | 📋 Ready |
| 1 | `infra/phase1-vpc` | VPC, Subnets, Route Tables | ✅ Deployed |
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

### 1. Apply Bootstrap (Phase 0) - Remote State Setup

```bash
cd infra/phase0-bootstrap
terraform init
terraform plan
terraform apply
```

### 2. Migrate Phase 1 to Remote State

After bootstrap is applied, update `infra/phase1-vpc/backend.tf` to use S3 backend,
then run:

```bash
cd infra/phase1-vpc
terraform init -migrate-state
```

### 3. Apply Subsequent Phases

```bash
cd infra/phase2-endpoints
terraform init
terraform plan
terraform apply
```

## State Management

- **Phase 0 (Bootstrap)**: Uses local state (intentional - bootstrap cannot use its own backend)
- **All other phases**: Use S3 backend with DynamoDB locking after bootstrap is applied

## Directory Structure

```
theraprac-infra/
├── README.md
├── infra/
│   ├── phase0-bootstrap/    # S3 + DynamoDB for Terraform state
│   ├── phase1-vpc/          # VPC & network foundation
│   ├── phase2-endpoints/    # VPC endpoints
│   ├── phase3-iam/          # IAM roles & policies
│   ├── phase4-ziti/         # Ziti zero-trust network
│   ├── phase5-rds/          # RDS PostgreSQL
│   ├── phase6-app/          # Application infrastructure
│   └── modules/             # Shared Terraform modules
```

