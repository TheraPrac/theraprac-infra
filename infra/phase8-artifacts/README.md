# Phase 8: Artifact Storage Lifecycle Management

## Overview

Manages S3 lifecycle policies for the `theraprac-api` artifact bucket to automatically clean up old builds while preserving important artifacts.

## What This Does

- **Applies lifecycle policies** to the existing `theraprac-api` S3 bucket
- **Auto-deletes old branch builds** after 30 days (configurable)
- **Keeps latest pointers** forever (they're overwritten on each build, so they stay fresh)
- **Keeps all releases** forever (immutable, permanent record)

## Lifecycle Rules

### Rule 1: Delete Old Branch Builds
- **Target**: `builds/*/*/` (individual commit builds)
- **Action**: Delete objects older than 30 days
- **Note**: Latest pointers (`builds/{branch}/latest/`) are overwritten on each build, so they stay fresh and won't be deleted

### Rule 2: Keep Releases Forever
- **Target**: `releases/*`
- **Action**: No expiration (kept forever)

## Usage

```bash
cd infra/phase8-artifacts
terraform init
terraform plan
terraform apply
```

## Configuration

Edit `variables.tf` or use `terraform.tfvars`:

```hcl
artifact_bucket_name        = "theraprac-api"
branch_build_retention_days = 30
```

## Important Notes

- This module assumes the `theraprac-api` bucket already exists
- It only manages lifecycle policies, not the bucket itself
- Latest pointers are preserved because they're overwritten on each build (staying fresh)
- Individual commit builds are deleted after the retention period

