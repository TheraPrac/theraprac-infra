# TheraPrac Basic Server Ansible Playbooks

Ansible playbooks for provisioning and configuring TheraPrac servers with Ziti overlay access.

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `playbook.yml` | Provision basic server with Ziti SSH access |
| `add-https.yml` | Add HTTPS services to existing server |
| `cleanup-ziti.yml` | **Clean up Ziti resources before destroying server** |

## Roles

| Role | Purpose |
|------|---------|
| `ziti-install` | Install Ziti binaries |
| `ziti-identity` | Create identity on Ziti controller |
| `ziti-enroll` | Enroll identity on server |
| `ziti-service` | Register SSH service |
| `certbot` | Get Let's Encrypt certificates via DNS-01 |
| `nginx` | Configure nginx reverse proxy with TLS |
| `ziti-https-service` | Register HTTPS services with Ziti |
| `mock-backends` | Simple HTTP services for testing (optional) |

---

## ⚠️ IMPORTANT: Cleanup Before Terraform Destroy

**You MUST clean up Ziti resources before destroying a server with Terraform!**

When you destroy a basic server with Terraform, the EC2 instance is terminated, but the Ziti resources (identities, services, configs, policies) remain in the Ziti controller. This creates orphaned resources that can cause issues.

**Note:** The cleanup connects directly to the Ziti controller API - the server does NOT need to be running or accessible. You can even run cleanup after the server is terminated to clean up orphaned resources.

### Quick Cleanup

```bash
# Use the wrapper script (recommended)
./scripts/cleanup-basic-server-ziti.sh <name> <role> <environment>
./scripts/cleanup-basic-server-ziti.sh app mt nonprod

# Or run the playbook directly
ansible-playbook -i inventory/server-eice.yml cleanup-ziti.yml \
  -e "server_name=app.mt.nonprod" \
  -e "ziti_ssh_name=ssh.app.mt.nonprod.ziti" \
  -e "ziti_identity_name=basic-server-app-mt-nonprod" \
  -e "ziti_controller_endpoint=https://ziti-nonprod.theraprac.com"
```

### What Gets Cleaned Up

- Ziti identity (e.g., `basic-server-app-mt-nonprod`)
- SSH service (e.g., `ssh.app.mt.nonprod.ziti`)
- SSH configs (host.v1 and intercept.v1)
- SSH bind policy
- HTTPS services (if they were added)
- HTTPS configs and policies (if they were added)

### Audit Current Resources

To see what Ziti resources currently exist:

```bash
./scripts/list-ziti-resources.sh
```

This will show all identities, services, configs, and policies in your Ziti controller.

---

## Basic Server Provisioning

Provisions a server with Ziti SSH access.

### Prerequisites

1. Terraform Phase 7 applied (EC2 instance created)
2. AWS credentials configured

### Usage

```bash
# Interactive provisioning (recommended)
./scripts/provision-basic-server.sh

# Manual playbook run
ansible-playbook -i inventory/server-eice.yml playbook.yml \
  -e "server_name=app.mt.dev" \
  -e "ziti_ssh_name=ssh.app.mt.dev.ziti" \
  -e "ziti_identity_name=basic-server-app-mt-dev" \
  -e "ziti_controller_endpoint=https://ziti-dev.theraprac.com"
```

---

## Add HTTPS Services

Adds nginx, TLS certificates, and Ziti HTTPS services to an existing server.

### Prerequisites

1. Server already provisioned with `playbook.yml`
2. `ziti-edge-tunnel` running and enrolled
3. IAM role has Route53 permissions (applied via Terraform phase3-iam)

### Usage

```bash
# Via Ziti (preferred - requires ZDE running)
ansible-playbook -i inventory/ziti.yml add-https.yml \
  --limit ssh.app.mt.dev.ziti \
  -e "environment=dev" \
  -e "ziti_identity_name=basic-server-app-mt-dev" \
  -e "ziti_controller_endpoint=https://ziti-dev.theraprac.com"

# Via EICE (if Ziti not available)
ansible-playbook -i inventory/server-eice.yml add-https.yml \
  -e "environment=dev" \
  -e "ziti_identity_name=basic-server-app-mt-dev" \
  -e "ziti_controller_endpoint=https://ziti-dev.theraprac.com"
```

### Domain Naming Convention

| Environment | Web App | API |
|-------------|---------|-----|
| dev | `app-dev.theraprac.com` | `api-dev.theraprac.com` |
| test | `app-test.theraprac.com` | `api-test.theraprac.com` |
| prod | `app-prod.theraprac.com` | `api-prod.theraprac.com` |

### Testing with Mock Backends

For testing the nginx and Ziti configuration before deploying real applications, you can enable mock HTTP services:

```bash
# Deploy with mock backends for testing
ansible-playbook -i inventory/ziti.yml add-https.yml \
  --limit ssh.app.mt.dev.ziti \
  -e "environment=dev" \
  -e "ziti_identity_name=basic-server-app-mt-dev" \
  -e "ziti_controller_endpoint=https://ziti-dev.theraprac.com" \
  -e "deploy_mock_backends=true"
```

The mock services provide:
- Simple HTTP servers on ports 3000 and 8080
- `/health` endpoint returning JSON health status
- `/` endpoint returning service info
- Systemd services (`mock-app`, `mock-api`) for easy management

To stop mock services when ready for real apps:
```bash
sudo systemctl stop mock-app mock-api
sudo systemctl disable mock-app mock-api
```

### What Gets Created

1. **Let's Encrypt Certificates** (via certbot DNS-01)
   - `/etc/letsencrypt/live/app-{env}.theraprac.com/`
   - Auto-renewal via systemd timer

2. **Nginx Configuration**
   - Listens on `127.0.0.1:443` (only accessible via Ziti)
   - Proxies to `localhost:3000` (Next.js) and `localhost:8080` (Go API)

3. **Ziti Services**
   - `app-{env}.theraprac.com` → nginx → Next.js
   - `api-{env}.theraprac.com` → nginx → Go API

---

## Dial Policies (One-Time Setup)

After adding HTTPS services, you need dial policies so users can access them.
Run these commands once on the Ziti controller (or via any authenticated ziti CLI):

```bash
# Allow users to dial web services
ziti edge create service-policy web-dial Dial \
  --identity-roles "#users" \
  --service-roles "#web-services"

# Allow users/developers to dial API services
ziti edge create service-policy api-dial Dial \
  --identity-roles "#users,#developers" \
  --service-roles "#api-services"
```

### Verify Policies

```bash
# List dial policies
ziti edge list service-policies

# Check specific policy
ziti edge list service-policies 'name="web-dial"'
```

---

## Inventories

| Inventory | Purpose |
|-----------|---------|
| `inventory/ziti.yml` | Connect via Ziti overlay (requires ZDE) |
| `inventory/server-eice.yml` | Connect via EC2 Instance Connect (break-glass) |

### Using Ziti Inventory

Requires Ziti Desktop Edge (ZDE) running with an enrolled identity:

```bash
ansible-playbook -i inventory/ziti.yml add-https.yml \
  --limit ssh.app.mt.dev.ziti \
  -e "environment=dev" \
  ...
```

### Using EICE Inventory

For break-glass access when Ziti is not available:

```bash
# Update instance ID in inventory first
sed -i 's/INSTANCE_ID/i-xxxxxxxxxxxx/' inventory/server-eice.yml

# Run playbook
ansible-playbook -i inventory/server-eice.yml add-https.yml \
  -e "environment=dev" \
  ...
```

---

## Troubleshooting

### Certificate Issues

```bash
# Check certificate status
sudo certbot certificates

# Force renewal
sudo certbot renew --force-renewal

# Check renewal timer
systemctl status certbot-renew.timer
```

### Nginx Issues

```bash
# Check nginx config
sudo nginx -t

# Check nginx status
systemctl status nginx

# View logs
sudo tail -f /var/log/nginx/*.log
```

### Ziti Issues

```bash
# Check tunnel status
systemctl status ziti-edge-tunnel@<identity-name>

# View tunnel logs
sudo tail -f /opt/ziti/logs/<identity-name>.log

# List services
ziti edge list services

# Check if services are bound
ziti edge list terminators
```

