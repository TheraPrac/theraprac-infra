# TheraPrac Infrastructure

AWS infrastructure deployment for TheraPrac using Terraform and Ansible.

## Phases

| Phase | Directory | Description | Status |
|-------|-----------|-------------|--------|
| 0 | `infra/phase0-bootstrap` | S3 + DynamoDB for Terraform state | ✅ Deployed |
| 1 | `infra/phase1-vpc` | VPC, Subnets, Route Tables | ✅ Deployed |
| 2 | `infra/phase2-endpoints` | NAT Gateway + S3 Endpoint | ✅ Deployed |
| 3 | `infra/phase3-iam` | IAM Roles & Policies | ✅ Deployed |
| 4 | `infra/phase4-ziti` | Ziti Network Infrastructure | ✅ Deployed |
| 5 | `infra/phase5-rds` | RDS PostgreSQL | 📋 Planned |
| 6 | `infra/phase6-app` | Application Infrastructure | 📋 Planned |

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI v2 with SSO profile `jfinlinson_admin`
- Ansible >= 2.14 with amazon.aws collection
- Session Manager plugin (for Ansible SSM connections)

## Quick Start

### 1. AWS Authentication

```bash
# Use the helper script to authenticate and export credentials
source scripts/aws-auth.sh
```

### 2. Terraform Workflow

Always use plan files to ensure consistent applies:

```bash
# Option A: Use wrapper scripts (recommended)
scripts/tf-plan.sh phase4-ziti
scripts/tf-apply.sh phase4-ziti

# Option B: Manual commands
cd infra/phase4-ziti
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Ansible Deployment

```bash
cd ansible/ziti-nonprod
ansible-playbook -i inventory/aws_ssm.yml playbook.yml
```

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `scripts/aws-auth.sh` | Authenticate via AWS SSO and export credentials |
| `scripts/tf-plan.sh` | Run terraform plan with output file |
| `scripts/tf-apply.sh` | Apply a terraform plan file |

### Usage Examples

```bash
# Authenticate to AWS
source scripts/aws-auth.sh

# Plan a specific phase
scripts/tf-plan.sh phase4-ziti

# Apply the plan
scripts/tf-apply.sh phase4-ziti
```

## State Management

- **Phase 0 (Bootstrap)**: Uses local state (bootstrap cannot use its own backend)
- **All other phases**: Use S3 backend with DynamoDB locking

## Directory Structure

```
theraprac-infra/
├── README.md
├── scripts/
│   ├── aws-auth.sh          # AWS SSO authentication helper
│   ├── tf-plan.sh           # Terraform plan wrapper
│   └── tf-apply.sh          # Terraform apply wrapper
├── infra/
│   ├── phase0-bootstrap/    # S3 + DynamoDB for Terraform state
│   ├── phase1-vpc/          # VPC & network foundation
│   ├── phase2-endpoints/    # NAT Gateway + S3 endpoint
│   ├── phase3-iam/          # IAM roles & policies
│   ├── phase4-ziti/         # Ziti zero-trust network
│   ├── phase5-rds/          # RDS PostgreSQL (planned)
│   └── phase6-app/          # Application (planned)
└── ansible/
    └── ziti-nonprod/        # Ziti installation playbook
```

## DNS

| Name | Type | Target |
|------|------|--------|
| `ziti-nonprod.theraprac.com` | Public | ALB (Ziti controller) |
| `ziti-instance-nonprod.theraprac-internal.com` | Private | Ziti EC2 instance |

## Post-Deployment Verification

```bash
# Test ALB health check
curl -I https://ziti-nonprod.theraprac.com/

# Test Ziti API (after Ansible deployment)
curl -sk https://ziti-nonprod.theraprac.com/edge/client/v1/version
```
