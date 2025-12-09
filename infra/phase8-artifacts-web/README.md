# Phase 8: Web Artifact Storage

Manages the S3 bucket and lifecycle policies for TheraPrac Web build artifacts.

## Overview

This module:
- Creates the `theraprac-web` S3 bucket
- Enables versioning for safety
- Applies lifecycle policies for automatic cleanup
- Blocks public access

## S3 Structure

```
theraprac-web/
├── builds/                          # Environment builds (mutable)
│   ├── dev/
│   │   ├── main/
│   │   │   ├── v0.1.0-dev.1/       # Specific version (30 day retention)
│   │   │   └── latest/              # Latest pointer (stays fresh)
│   │   └── feature-xyz/
│   │       ├── v0.1.0-dev.2/
│   │       └── latest/
│   ├── test/
│   │   └── {branch}/
│   │       ├── {tag}/
│   │       └── latest/
│   └── prod/
│       └── {branch}/
│           ├── {tag}/
│           └── latest/
└── releases/                        # Final releases (immutable, forever)
    └── v0.1.0/
```

## Lifecycle Rules

### Rule 1: Delete Old Environment Builds

- **Path**: `builds/*`
- **Action**: Delete objects older than 30 days
- **Note**: Latest pointers (`builds/{env}/{branch}/latest/`) are overwritten on each build, so they stay fresh and won't be deleted

### Rule 2: Keep Releases Forever

- **Path**: `releases/*`
- **Action**: No expiration (kept forever)
- **Note**: Releases are immutable and should never be deleted

## Usage

### Initialize and Apply

```bash
cd infra/phase8-artifacts-web
terraform init
terraform plan
terraform apply
```

### Custom Retention Period

```bash
terraform apply -var="build_retention_days=60"
```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `aws_region` | AWS region | `us-west-2` |
| `bucket_name` | S3 bucket name | `theraprac-web` |
| `build_retention_days` | Days to retain builds | `30` |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_name` | Name of the S3 bucket |
| `bucket_arn` | ARN of the S3 bucket |
| `bucket_domain_name` | Domain name of the bucket |
| `lifecycle_policy_status` | Summary of lifecycle rules |

## Important Notes

- This module creates the bucket if it doesn't exist
- Lifecycle policies apply immediately but deletions happen on S3's schedule
- Latest pointers stay fresh because they're overwritten on each build
- Releases are permanent and should only be created for production-ready versions

