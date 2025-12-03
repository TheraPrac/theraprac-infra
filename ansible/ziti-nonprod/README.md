# TheraPrac Ziti Nonprod Ansible Playbook

Installs and configures OpenZiti controller + router on the nonprod EC2 instance.

## Prerequisites

1. **Terraform Phase 4 applied** - The Ziti EC2 instance must exist:
   ```bash
   cd ../../infra/phase4-ziti
   terraform apply
   ```

2. **AWS CLI configured**:
   ```bash
   aws sso login --profile jfinlinson_admin
   ```

3. **Ansible AWS collection**:
   ```bash
   ansible-galaxy collection install amazon.aws
   pip install boto3 botocore
   ```

4. **Session Manager plugin** (macOS):
   ```bash
   brew install session-manager-plugin
   ```

## Usage

```bash
cd ansible/ziti-nonprod
ansible-playbook -i inventory/aws_ssm.yml playbook.yml
```

### Run specific tasks

```bash
# Install only
ansible-playbook -i inventory/aws_ssm.yml playbook.yml --tags install

# PKI only
ansible-playbook -i inventory/aws_ssm.yml playbook.yml --tags pki

# Controller only
ansible-playbook -i inventory/aws_ssm.yml playbook.yml --tags controller
```

## Directory Structure

```
ansible/ziti-nonprod/
├── inventory/
│   └── aws_ssm.yml          # Dynamic inventory via SSM
├── playbook.yml             # Main playbook
├── README.md
└── roles/
    └── ziti/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── install.yml
        │   ├── pki.yml
        │   ├── controller.yml
        │   ├── router.yml
        │   ├── healthcheck.yml
        │   └── systemd.yml
        └── templates/
            ├── controller.yaml.j2
            ├── router.yaml.j2
            ├── ziti-controller.service.j2
            ├── ziti-router.service.j2
            └── healthcheck.service.j2
```

## What Gets Installed

| Component | Location |
|-----------|----------|
| Ziti binary | `/opt/ziti/bin/ziti` |
| PKI certs | `/opt/ziti/pki/` |
| Controller config | `/opt/ziti/controller/controller.yaml` |
| Controller DB | `/opt/ziti/controller/ctrl.db` |
| Admin password | `/opt/ziti/controller/.admin_password` |
| Router config | `/opt/ziti/router/router.yaml` |
| Health check | `/opt/ziti/healthcheck/healthcheck.py` |

## Services

| Service | Port | Purpose |
|---------|------|---------|
| ziti-controller | 443 | Ziti management/client API |
| ziti-router | 8442 | Edge router for SDK clients |
| healthcheck | 8080 | ALB health check endpoint |

## Variables

Key variables in `roles/ziti/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `ziti_install_dir` | `/opt/ziti` | Base installation directory |
| `ziti_controller_port` | `443` | Controller API port |
| `ziti_healthcheck_port` | `8080` | Health check port |
| `ziti_public_endpoint` | `ziti-nonprod.theraprac.com` | Public DNS name |
| `ziti_private_dns_name` | `ziti-instance-nonprod.theraprac-internal.com` | Private DNS |

## Troubleshooting

### Check service status
```bash
# SSH via SSM
aws ssm start-session --target <instance-id> --profile jfinlinson_admin

# Check services
systemctl status ziti-controller
systemctl status ziti-router
systemctl status healthcheck
```

### View logs
```bash
journalctl -u ziti-controller -f
journalctl -u ziti-router -f
```

### Test health check
```bash
curl http://localhost:8080/
```

### Get admin password
```bash
cat /opt/ziti/controller/.admin_password
```

---

## Ziti Services and Policies

### Synthetic DNS Names

Ziti uses **synthetic DNS names** for services on the overlay network. These are NOT real DNS records - they only resolve when connected to the Ziti network via `ziti-edge-tunnel`.

**Naming Convention:**
```
<function>.<environment>.ziti
```

| Purpose | Synthetic DNS Name | Description |
|---------|-------------------|-------------|
| SSH access | `ssh.ziti-nonprod.ziti` | SSH to the Ziti server |
| Controller | `controller.ziti-nonprod.ziti` | Controller management (future) |
| Router | `router.ziti-nonprod.ziti` | Router management (future) |
| App services | `*.theraprac.com.ziti` | Application dark services (future) |

**Rules:**
- All dark services end with `.ziti`
- Environment prefix: `nonprod`, `prod`
- Subdomain = function: `ssh`, `api`, `db`, etc.

### SSH Service

The SSH service allows authorized Ziti identities to SSH into the nonprod server through the zero-trust overlay network.

**Service Details:**
- **Name:** `ssh.ziti-nonprod`
- **Synthetic DNS:** `ssh.ziti-nonprod.ziti`
- **Backend:** `127.0.0.1:22` (localhost on router)
- **Access:** Requires `role.ssh` attribute

### Setting Up SSH Service

```bash
# Login to Ziti controller
ziti edge login https://ziti-nonprod.theraprac.com --username admin --password <password>

# Run setup scripts
cd scripts/ziti
./setup-all.sh

# Or run individually:
./setup-ssh-service.sh   # Create the service
./setup-ssh-bind.sh      # Bind policy (router hosts service)
./setup-ssh-dial.sh      # Dial policy (users access service)
```

### Creating User Identities

```bash
# Create user with SSH access
./create-user.sh joe-dev --ssh

# Create user without SSH (can add later)
./create-user.sh bob-read

# Grant SSH to existing user
ziti edge update identity bob-read --role-attributes role.ssh
```

### Connecting via SSH

**On your local machine:**

1. **Enroll your identity** (one-time):
   ```bash
   ziti edge enroll your-name.jwt -o ~/.config/ziti/identities/your-name.json
   ```

2. **Start the tunnel**:
   ```bash
   # macOS/Linux
   sudo ziti-edge-tunnel run ~/.config/ziti/identities/your-name.json
   
   # Or use Ziti Desktop Edge app
   ```

3. **SSH to the server**:
   ```bash
   ssh ec2-user@ssh.ziti-nonprod.ziti
   ```

### Verifying Configuration

```bash
# Run verification script
./verify-ssh-service.sh

# Manual checks
ziti edge list services | grep ssh
ziti edge list service-policies | grep ssh
ziti edge list identities
```

### Role Attributes

| Attribute | Access |
|-----------|--------|
| `role.ssh` | Can SSH to nonprod server |
| `role.admin` | Admin-level access (future) |
| `role.dev` | Developer access (future) |

### Troubleshooting SSH Access

**Can't resolve `ssh.ziti-nonprod.ziti`:**
- Ensure `ziti-edge-tunnel` is running
- Check your identity has `role.ssh` attribute

**Connection refused:**
- Verify router is online: `ziti edge list edge-routers`
- Check bind policy exists: `ziti edge list service-policies | grep bind`

**Permission denied:**
- Ensure you're using the correct SSH user: `ec2-user`
- Check SSH key is configured on the server
