# Branch Build Deployment Guide

## Overview

The deployment system now supports deploying from branch builds, not just releases. This allows you to test specific commits before they're tagged as releases.

## Supported Version Formats

1. **`latest`** - Deploys from `builds/main/latest/` (or first available branch latest)
2. **`0.1.0`** - Deploys from `releases/v0.1.0/` (tagged release)
3. **`branch/latest`** - Deploys from `builds/branch/latest/` (e.g., `fix/remaining-lint-errors/latest`)
4. **`branch/commit`** - Deploys from `builds/branch/commit/` (e.g., `fix/remaining-lint-errors/74dc437`)

## Usage

### List Available Builds

```bash
./scripts/list-builds.sh
```

This shows:
- All branch builds from last 30 days (configurable)
- Up to 10 most recent commits per branch
- All releases
- Only shows builds with valid manifests and tarballs

### Deploy from Branch Build

```bash
# Deploy latest from a branch
./scripts/deploy-api.sh dev app.mt.dev fix/remaining-lint-errors/latest

# Deploy specific commit
./scripts/deploy-api.sh dev app.mt.dev fix/remaining-lint-errors/74dc437

# Deploy from main latest
./scripts/deploy-api.sh dev app.mt.dev latest

# Deploy from release
./scripts/deploy-api.sh dev app.mt.dev 0.1.0
```

### Pre-flight Check

```bash
# Check before deploying
./scripts/preflight-deploy-api.sh dev app.mt.dev fix/remaining-lint-errors/74dc437
```

## Build Retention

- **Branch builds (individual commits)**: Auto-deleted after 30 days via S3 lifecycle policy
- **Branch `latest` pointers**: Kept forever (overwritten on each build, so they stay fresh)
- **Releases**: Kept forever (immutable, permanent record)

## Implementation Details

### Ansible Role Changes

The `theraprac-api` role now:
- Detects version type (latest, branch build, or release)
- Downloads manifest to get actual version
- Constructs correct S3 path based on version format

### S3 Lifecycle Policies

Terraform module `phase8-artifacts` manages:
- Automatic deletion of old branch builds (30 days)
- Permanent retention of releases
- Latest pointers stay fresh (overwritten on each build)

### Build Validation

The `list-builds.sh` script:
- Only shows builds with valid manifests
- Verifies tarball exists
- Filters by date (last 30 days)
- Limits to 10 most recent per branch

## Benefits

1. **Test before release**: Deploy specific commits to test environments
2. **Rollback capability**: Deploy previous commits if needed
3. **Automatic cleanup**: Old builds are automatically deleted
4. **Clear visibility**: Easy to see what builds are available


