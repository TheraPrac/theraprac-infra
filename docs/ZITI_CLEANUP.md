# Ziti Cleanup Guide

## Overview

When you destroy a basic server using Terraform, the EC2 instance is terminated, but the Ziti resources (identities, services, configs, policies) remain in the Ziti controller. This creates orphaned resources that can cause issues.

**You MUST clean up Ziti resources BEFORE destroying a server with Terraform.**

### Important Note

The cleanup process connects directly to the Ziti controller API from your local machine. **The server does NOT need to be running or accessible.** This means:

- ✅ You can run cleanup before destroying the server (recommended)
- ✅ You can run cleanup after destroying the server (to clean up orphaned resources)
- ✅ You can run cleanup even if the server is already terminated
- ❌ You do NOT need SSH access to the server
- ❌ You do NOT need the server to be running

## Quick Start

### 1. List Current Resources

First, audit what Ziti resources currently exist:

```bash
./scripts/list-ziti-resources.sh
```

This will show:
- All identities (including basic-server identities)
- All services (SSH and HTTPS)
- All configs (host.v1, intercept.v1)
- All policies (bind, dial, service edge router policies)

### 2. Clean Up Before Destroy

Before destroying a server, run the cleanup script:

```bash
./scripts/cleanup-basic-server-ziti.sh <name> <role> <environment>
./scripts/cleanup-basic-server-ziti.sh app mt nonprod
```

The script will:
1. Show what will be deleted
2. Ask for confirmation
3. Ask if HTTPS services were added (optional)
4. Run the Ansible cleanup playbook
5. Confirm when cleanup is complete

### 3. Destroy with Terraform

After cleanup is complete, it's safe to destroy the server:

```bash
cd infra/phase7-basic-server
terraform destroy \
  -var="name=app" \
  -var="role=mt" \
  -var="tier=app" \
  -var="environment=nonprod"
```

## What Gets Cleaned Up

For each basic server, the cleanup removes:

### Identity
- Identity name: `basic-server-{name}-{role}-{environment}`
- Example: `basic-server-app-mt-nonprod`

### SSH Service
- Service name: `ssh.{name}.{role}.{environment}.ziti`
- Example: `ssh.app.mt.nonprod.ziti`
- Host config: `ssh.app.mt.nonprod.ziti.host`
- Intercept config: `ssh.app.mt.nonprod.ziti.intercept`
- Bind policy: `ssh.app.mt.nonprod.ziti-bind`

### HTTPS Services (if added)
- Web service: `https.{app_domain}`
- API service: `https.{api_domain}`
- Configs and policies for each service

## Manual Cleanup

If you need to run the cleanup playbook directly:

```bash
cd ansible/basic-server
ansible-playbook -i inventory/server-eice.yml cleanup-ziti.yml \
  -e "server_name=app.mt.nonprod" \
  -e "ziti_ssh_name=ssh.app.mt.nonprod.ziti" \
  -e "ziti_identity_name=basic-server-app-mt-nonprod" \
  -e "ziti_controller_endpoint=https://ziti-nonprod.theraprac.com"
```

If HTTPS services were added:

```bash
ansible-playbook -i inventory/server-eice.yml cleanup-ziti.yml \
  -e "server_name=app.mt.nonprod" \
  -e "ziti_ssh_name=ssh.app.mt.nonprod.ziti" \
  -e "ziti_identity_name=basic-server-app-mt-nonprod" \
  -e "ziti_controller_endpoint=https://ziti-nonprod.theraprac.com" \
  -e "app_domain=app-dev.theraprac.com" \
  -e "api_domain=api-dev.theraprac.com"
```

## Troubleshooting

### Identity Not Found

If the identity was already deleted, the cleanup will skip it. This is safe.

### Service Not Found

If services were already deleted, the cleanup will skip them. This is safe.

### Cleanup Fails Partway Through

If cleanup fails partway through, you can run it again. The playbook is idempotent and will skip resources that don't exist.

### Cleaning Up Orphaned Resources

If you have orphaned resources from previous destroys (server already terminated), you can clean them up the same way:

```bash
# Clean up orphaned resources for a server that's already gone
./scripts/cleanup-basic-server-ziti.sh app mt nonprod
```

The cleanup script works the same way whether the server is running or not, since it only connects to the Ziti controller API.

### Manual Cleanup

If you prefer to manually delete orphaned resources:

```bash
# Login to Ziti
ziti edge login https://ziti-nonprod.theraprac.com --username admin

# List identities
ziti edge list identities

# Delete specific identity
ziti edge delete identity basic-server-app-mt-nonprod

# List services
ziti edge list services

# Delete specific service
ziti edge delete service ssh.app.mt.nonprod.ziti

# List configs
ziti edge list configs

# Delete specific config
ziti edge delete config ssh.app.mt.nonprod.ziti.host
```

## Best Practices

1. **Always audit first**: Run `list-ziti-resources.sh` before cleanup to see what exists
2. **Clean up before destroy**: Never destroy a server without cleaning up Ziti resources first
3. **Verify cleanup**: After cleanup, run `list-ziti-resources.sh` again to confirm resources are gone
4. **Document HTTPS services**: If you added HTTPS services, make note of the domains so you can clean them up later

## Related Documentation

- [Basic Server README](../ansible/basic-server/README.md) - Provisioning and configuration
- [Ziti Manual Setup](../docs/ZITI_MANUAL_SETUP.md) - Ziti controller setup
- [Provision Script](../scripts/provision-basic-server.sh) - Server provisioning script

