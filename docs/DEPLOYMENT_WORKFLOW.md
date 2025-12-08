# TheraPrac API Deployment Workflow

## Overview

This guide explains how all the deployment scripts work together to deploy the TheraPrac API from build artifacts to production servers.

## Complete Deployment Workflow

```
1. Build (GitHub Actions)
   └─ Builds Go binary
   └─ Packages tarball with binary + migrations
   └─ Uploads to S3 (builds/{branch}/{commit}/ or releases/v{version}/)

2. List Available Builds
   └─ ./scripts/list-builds.sh
   └─ Shows valid builds from last 30 days
   └─ Shows all releases

3. Pre-flight Check (Optional but Recommended)
   └─ ./scripts/preflight-deploy-api.sh <env> <server> <version>
   └─ Validates all prerequisites before deployment

4. Deploy
   └─ ./scripts/deploy-api.sh <env> <server> <version>
   └─ Updates SSM parameters
   └─ Runs Ansible playbook
   └─ Installs Liquibase (if needed)
   └─ Downloads and extracts tarball
   └─ Runs database migrations
   └─ Deploys application
   └─ Starts service
```

## Scripts Overview

### 1. `list-builds.sh`

**Purpose**: List all available API builds from S3

**Usage**:
```bash
./scripts/list-builds.sh
```

**What it does**:
- Lists branch builds from last 30 days (configurable via `MAX_AGE_DAYS`)
- Shows up to 10 most recent commits per branch
- Lists all releases (no date filter)
- Validates builds (checks manifest and tarball exist)
- Shows invalid builds with warnings

**Output example**:
```
Branch Builds:
  Branch: fix/remaining-lint-errors
    latest:
      Version: 0.1.0
      Commit:  74dc437
      Built:   2025-12-08T19:44:34Z
      Deploy:  ./scripts/deploy-api.sh <env> <server> fix/remaining-lint-errors/latest
    Recent commits:
      74dc437: 0.1.0 (2025-12-08T19:44:34Z)
        Deploy: ./scripts/deploy-api.sh <env> <server> fix/remaining-lint-errors/74dc437

Releases:
  v0.1.0-dev.1:
    Version: 0.1.0
    Commit:  f68d23f
    Built:   2025-12-05T04:04:07Z
    Deploy:  ./scripts/deploy-api.sh <env> <server> 0.1.0-dev.1
```

**When to use**: Before deploying, to see what builds are available

---

### 2. `preflight-deploy-api.sh`

**Purpose**: Validate all prerequisites before deployment

**Usage**:
```bash
./scripts/preflight-deploy-api.sh <environment> <server-name> <version>
```

**Parameters**:
- `environment`: `dev`, `test`, `prod`, or `nonprod`
- `server-name`: Server name (e.g., `app.mt.dev`, `theraprac.mt.nonprod`)
- `version`: Version to deploy (see [Supported Version Formats](#supported-version-formats))

**What it checks**:
1. ✅ AWS credentials
2. ✅ SSM parameters (db-host, db-port, db-name, etc.)
3. ✅ Secrets Manager (DB_ADMIN_PASSWORD, DB_PASSWORD)
4. ✅ S3 artifact exists and contains migrations
5. ✅ Ziti database service is reachable
6. ✅ Database connectivity (real connection test)
7. ✅ Ansible roles and playbooks exist
8. ✅ Target server configuration (inventory, SSH key, reachability)
9. ✅ Liquibase availability on target server

**Output**: Summary with errors and warnings

**When to use**: Always before deploying to catch issues early

**Deploy Integration**: If all checks pass (or only warnings), the script will prompt to deploy immediately:
- **All checks pass**: Prompts "Deploy now? [Y/n]" (defaults to Yes)
- **Warnings only**: Prompts "Deploy anyway? [y/N]" (defaults to No)
- **Errors found**: Exits with error, no deploy prompt

If you choose to deploy, it automatically runs `deploy-api.sh` with the same parameters.

**Example**:
```bash
./scripts/preflight-deploy-api.sh dev app.mt.dev fix/remaining-lint-errors/74dc437
# If checks pass, you'll be prompted:
# Deploy now? [Y/n]:
# Press Enter to deploy, or 'n' to cancel
```

---

### 3. `deploy-api.sh`

**Purpose**: Deploy the API to a target server

**Usage**:
```bash
./scripts/deploy-api.sh [--non-interactive|-y] [--bootstrap]
```

**Interactive mode** (default):
- Prompts for environment, server name, and version
- Caches values for next run
- Shows deployment summary

**Non-interactive mode**:
```bash
./scripts/deploy-api.sh --non-interactive
# Or with -y flag
./scripts/deploy-api.sh -y
```

**What it does**:
1. Validates AWS credentials
2. Checks/creates IAM roles (if `--bootstrap` flag used)
3. Validates AWS resources exist
4. **Updates SSM parameter** `db-host` to Ziti service name
5. Runs Ansible playbook (`deploy-api.yml`):
   - Installs Liquibase (if needed)
   - Downloads tarball from S3
   - Extracts tarball (binary + migrations)
   - Retrieves DB credentials from SSM/Secrets Manager
   - Runs Liquibase migrations via Ziti
   - Deploys binary
   - Creates environment file
   - Installs systemd service
   - Starts service
6. Health check

**Supported Version Formats**:

| Format | Example | S3 Path |
|--------|---------|---------|
| `latest` | `latest` | `builds/main/latest/` |
| `branch/latest` | `fix/remaining-lint-errors/latest` | `builds/fix/remaining-lint-errors/latest/` |
| `branch/commit` | `fix/remaining-lint-errors/74dc437` | `builds/fix/remaining-lint-errors/74dc437/` |
| `version` | `0.1.0-dev.1` | `releases/v0.1.0-dev.1/` |

**When to use**: To deploy the API to a server

**Example**:
```bash
# Interactive
./scripts/deploy-api.sh
# Then enter: dev, app.mt.dev, fix/remaining-lint-errors/74dc437

# Or use cached values from last run
./scripts/deploy-api.sh
# Press Enter to use cached values
```

---

## Typical Workflow Examples

### Example 1: Deploy Latest from Branch

```bash
# 1. See what builds are available
./scripts/list-builds.sh

# 2. Pre-flight check (will prompt to deploy if checks pass)
./scripts/preflight-deploy-api.sh dev app.mt.dev fix/remaining-lint-errors/latest
# If all checks pass, you'll be prompted: "Deploy now? [Y/n]:"
# Press Enter to deploy automatically, or 'n' to cancel
```

### Example 2: Deploy Specific Commit

```bash
# 1. List builds to find commit hash
./scripts/list-builds.sh

# 2. Pre-flight check (will prompt to deploy if checks pass)
./scripts/preflight-deploy-api.sh dev app.mt.dev fix/remaining-lint-errors/74dc437
# If all checks pass, you'll be prompted: "Deploy now? [Y/n]:"
# Press Enter to deploy automatically, or 'n' to cancel
```

### Example 3: Deploy Release

```bash
# 1. List releases
./scripts/list-builds.sh

# 2. Pre-flight check (will prompt to deploy if checks pass)
./scripts/preflight-deploy-api.sh prod theraprac.mt.prod 0.1.0
# If all checks pass, you'll be prompted: "Deploy now? [Y/n]:"
# Press Enter to deploy automatically, or 'n' to cancel
```

---

## How Scripts Work Together

### Build → List → Pre-flight → Deploy

```
┌─────────────────┐
│ GitHub Actions  │
│ Build & Upload  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  S3 Artifacts   │
│ builds/         │
│ releases/       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│ list-builds.sh  │─────▶│ Shows available  │
│                 │      │ builds with       │
│                 │      │ validation        │
└─────────────────┘      └──────────────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│preflight-deploy │─────▶│ Validates all    │
│   -api.sh       │      │ prerequisites    │
│                 │      │ before deploy     │
└─────────────────┘      └──────────────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│ deploy-api.sh   │─────▶│ Deploys to server │
│                 │      │ via Ansible       │
│                 │      │ - Updates SSM     │
│                 │      │ - Runs migrations │
│                 │      │ - Deploys app     │
└─────────────────┘      └──────────────────┘
```

---

## Ansible Playbook Details

The `deploy-api.sh` script calls the Ansible playbook `ansible/basic-server/deploy-api.yml`, which:

1. **Installs Liquibase** (via `liquibase` role)
   - Downloads Liquibase from GitHub
   - Downloads PostgreSQL JDBC driver
   - Creates symlink `/usr/local/bin/liquibase`

2. **Deploys Application** (via `theraprac-api` role)
   - Detects version type (latest, branch build, or release)
   - Downloads manifest from S3 to get actual version
   - Downloads tarball from S3
   - Extracts tarball to staging directory
   - Copies binary to `/opt/theraprac/bin/`
   - Copies migrations to `/opt/theraprac/db/changelog/`
   - Retrieves DB credentials from SSM/Secrets Manager
   - Runs Liquibase migrations via Ziti (`postgres.db.{env}.app.ziti`)
   - Creates environment file
   - Installs systemd service
   - Starts service
   - Health check

---

## Environment Variables

### Required AWS Configuration

- AWS credentials configured (via `aws sso login --profile jfinlinson_admin`)
- S3 bucket: `theraprac-api` (default, can be overridden)
- SSM parameters: `/theraprac/api/{env}/*`
- Secrets Manager: `theraprac/api/{env}/secrets`

### Script Configuration

- `MAX_AGE_DAYS`: Days to show in `list-builds.sh` (default: 30)
- `MAX_COMMITS_PER_BRANCH`: Max commits per branch (default: 10)
- `S3_BUCKET`: S3 bucket name (default: `theraprac-api`)
- `AWS_PROFILE`: AWS profile to use (default: `jfinlinson_admin`)

---

## Troubleshooting

### Pre-flight Check Fails

**Issue**: Database connectivity fails
- **Check**: ZDE (Ziti Desktop Edge) is running
- **Check**: Ziti service `postgres.db.{env}.app.ziti` is active
- **Check**: SSM parameters are correct

**Issue**: S3 artifact not found
- **Check**: Build completed successfully in GitHub Actions
- **Check**: Version format is correct
- **Check**: Manifest exists in S3

**Issue**: SSH connectivity fails
- **Check**: Ansible SSH key exists: `~/.ssh/id_ed25519_ansible_1`
- **Check**: Server is reachable via Ziti: `ssh.{server}.ziti`
- **Check**: Server is in Ansible inventory

### Deployment Fails

**Issue**: Ansible playbook fails
- **Check**: Pre-flight check passed
- **Check**: AWS credentials are valid
- **Check**: Server has required permissions (IAM role)

**Issue**: Migrations fail
- **Check**: Liquibase is installed (will be installed automatically)
- **Check**: Database credentials are correct
- **Check**: Ziti service is reachable from server

---

## Related Documentation

- [Branch Build Deployment Guide](./BRANCH_BUILD_DEPLOYMENT.md) - Detailed branch build usage
- [Build Retention Strategy](./BUILD_RETENTION_STRATEGY.md) - How builds are retained/cleaned up
- [Ziti Roles and Policies](./ZITI_ROLES_AND_POLICIES.md) - Ziti access control

---

## Quick Reference

```bash
# List builds
./scripts/list-builds.sh

# Pre-flight check
./scripts/preflight-deploy-api.sh <env> <server> <version>

# Deploy
./scripts/deploy-api.sh

# Deploy with specific version (non-interactive)
./scripts/deploy-api.sh -y
# Then enter: dev, app.mt.dev, fix/remaining-lint-errors/74dc437
```

