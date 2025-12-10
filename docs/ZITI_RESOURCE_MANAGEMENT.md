# Ziti Resource Management and Cleanup

This document describes how to audit and maintain Ziti resources to prevent orphaned identities, services, policies, and other resources.

## Overview

Ziti resources can become orphaned when:
- Servers are destroyed without cleaning up Ziti resources first
- Services are deleted but configs remain
- Policies reference non-existent services or identities
- Terminators reference deleted services or routers
- Manual cleanup is incomplete

## Audit Scripts

### 1. List All Resources

Quick overview of all Ziti resources:

```bash
./scripts/list-ziti-resources.sh
```

This script provides a simple listing of:
- Identities
- Services
- Configs
- Service Policies
- Service Edge Router Policies

### 2. Comprehensive Audit

Detailed audit that identifies orphaned and problematic resources:

```bash
./scripts/audit-ziti-resources.sh [environment]
./scripts/audit-ziti-resources.sh nonprod
```

**What it checks:**
- Services without configs
- Configs not referenced by any service
- Service policies with no matching services/identities
- Terminators referencing non-existent services/routers
- Basic server identities that appear orphaned
- Sessions with invalid references

**Output:**
- Resource counts
- Critical issues (red)
- Warnings (yellow)
- Recommendations

### 3. Cleanup Orphaned Resources

Interactive cleanup script (requires confirmation for each deletion):

```bash
./scripts/cleanup-orphaned-ziti-resources.sh [environment] [--dry-run]
./scripts/cleanup-orphaned-ziti-resources.sh nonprod
./scripts/cleanup-orphaned-ziti-resources.sh nonprod --dry-run
```

**What it cleans:**
- Orphaned configs (not referenced by any service)
- Orphaned terminators (referencing deleted services/routers)
- Basic server identities with no active resources

**Safety:**
- Interactive prompts for each deletion
- Dry-run mode available
- Never deletes system resources

## Best Practices

### 1. Cleanup Before Destroying Servers

**ALWAYS** clean up Ziti resources before destroying a server with Terraform:

```bash
# For basic servers
./scripts/cleanup-basic-server-ziti.sh <name> <role> <environment>
./scripts/cleanup-basic-server-ziti.sh app mt nonprod

# Then destroy with Terraform
cd infra/phase7-basic-server
terraform destroy -var="name=app" -var="role=mt" -var="tier=app" -var="environment=nonprod"
```

### 2. Regular Audits

Run audits regularly to catch issues early:

```bash
# Monthly audit
./scripts/audit-ziti-resources.sh nonprod > audit-$(date +%Y-%m-%d).txt

# Review and address issues
./scripts/cleanup-orphaned-ziti-resources.sh nonprod --dry-run
```

### 3. Use Role Attributes

Always use role attributes in policies, not direct identity/service references:

**Good:**
```bash
ziti edge create service-policy ssh-bind Bind \
  --service-roles "#ssh-services" \
  --identity-roles "#routers"
```

**Bad:**
```bash
ziti edge create service-policy ssh-bind Bind \
  --service-roles "ssh-nonprod" \
  --identity-roles "router-1"
```

### 4. Naming Conventions

Follow consistent naming conventions to make audits easier:

- **Basic server identities**: `basic-server-{name}-{role}-{env}`
- **SSH services**: `ssh.{name}.{role}.{env}.ziti`
- **HTTPS services**: `https.{domain}`
- **Configs**: `{service-name}.host`, `{service-name}.intercept`
- **Policies**: `{service-name}-bind`, `{service-name}-dial`

### 5. Document Manual Changes

If you make manual changes via the Ziti CLI, document them:
- What was created/deleted
- Why
- When

This helps during audits to understand what resources should exist.

## Common Orphaned Resource Patterns

### Pattern 1: Destroyed Server Without Cleanup

**Symptom:**
- Basic server identity exists
- No related services
- No active sessions

**Solution:**
```bash
# Use the cleanup script
./scripts/cleanup-basic-server-ziti.sh <name> <role> <env>

# Or manually
ziti edge delete identity basic-server-<name>-<role>-<env>
```

### Pattern 2: Deleted Service, Configs Remain

**Symptom:**
- Configs exist but not referenced by any service
- Config names suggest they belonged to a service

**Solution:**
```bash
# Review with audit script
./scripts/audit-ziti-resources.sh nonprod

# Clean up with cleanup script
./scripts/cleanup-orphaned-ziti-resources.sh nonprod
```

### Pattern 3: Policy References Non-Existent Resources

**Symptom:**
- Service policy references service roles that don't match any services
- Identity roles that don't match any identities

**Solution:**
- Review policy and update role attributes
- Or delete policy if no longer needed

### Pattern 4: Terminators for Deleted Services

**Symptom:**
- Terminators exist but reference non-existent service IDs

**Solution:**
```bash
# Cleanup script will identify and offer to delete
./scripts/cleanup-orphaned-ziti-resources.sh nonprod
```

## Maintenance Schedule

### Weekly
- Quick resource listing: `./scripts/list-ziti-resources.sh`

### Monthly
- Full audit: `./scripts/audit-ziti-resources.sh nonprod`
- Review and address issues

### Quarterly
- Review all basic server identities
- Verify policies are using role attributes
- Check for unused configs

### Before Major Changes
- Run audit before infrastructure changes
- Clean up any issues found
- Document manual changes

## Troubleshooting

### Audit Script Fails to Login

**Problem:** Cannot connect to Ziti controller

**Solution:**
```bash
# Verify AWS credentials
aws sso login --profile jfinlinson_admin

# Check Secrets Manager path
aws secretsmanager get-secret-value \
  --secret-id ziti/nonprod/admin-password \
  --query SecretString --output text

# Verify Ziti endpoint is accessible
curl -sk https://ziti-nonprod.theraprac.com/edge/client/v1/version
```

### Cleanup Script Can't Delete Resource

**Problem:** Resource deletion fails

**Possible causes:**
- Resource is in use (active sessions)
- Resource is system-managed
- Insufficient permissions

**Solution:**
- Check for active sessions: `ziti edge list sessions`
- Review resource details: `ziti edge show <resource-type> <name>`
- Check if resource is system-managed
- May need to wait for sessions to close

### False Positives in Audit

**Problem:** Audit flags resources as orphaned but they're actually in use

**Solution:**
- Review resource details manually
- Check for active sessions
- Verify resource is referenced by policies
- Update audit script if pattern is common

## Related Scripts

- `scripts/list-ziti-resources.sh` - Quick resource listing
- `scripts/audit-ziti-resources.sh` - Comprehensive audit
- `scripts/cleanup-orphaned-ziti-resources.sh` - Interactive cleanup
- `scripts/cleanup-basic-server-ziti.sh` - Basic server cleanup
- `ansible/basic-server/cleanup-ziti.yml` - Ansible cleanup playbook

## See Also

- [Ziti Manual Setup](../docs/ZITI_MANUAL_SETUP.md)
- [Basic Server README](../ansible/basic-server/README.md)
- [Ziti Nonprod README](../ansible/ziti-nonprod/README.md)


