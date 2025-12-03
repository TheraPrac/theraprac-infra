# TheraPrac Ziti Nonprod Ansible Playbook

Installs and configures OpenZiti controller + router on the nonprod EC2 instance.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                       ┌───────▼───────┐
                       │   NLB (TCP)   │   ← TCP Passthrough (critical!)
                       │  Port 443     │
                       │  Port 8442    │
                       └───────┬───────┘
                               │
┌──────────────────────────────┼──────────────────────────────────┐
│  Private Subnet              │                                   │
│  ┌───────────────────────────▼────────────────────────────────┐ │
│  │                 Ziti EC2 Instance                          │ │
│  │  ┌─────────────────┐  ┌─────────────────┐                  │ │
│  │  │  Controller     │  │    Router       │                  │ │
│  │  │  Port 443       │  │  Port 8442      │                  │ │
│  │  │  Port 6262(ctrl)│  │                 │                  │ │
│  │  └─────────────────┘  └─────────────────┘                  │ │
│  │  ┌─────────────────┐                                       │ │
│  │  │  Healthcheck    │                                       │ │
│  │  │  Port 8080      │                                       │ │
│  │  └─────────────────┘                                       │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**IMPORTANT**: The NLB must use **TCP passthrough** (not TLS termination).
Router enrollment requires the controller's actual TLS certificate to verify JWTs.

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

3. **Ansible with AWS collection**:
   ```bash
   ansible-galaxy collection install amazon.aws
   pip install boto3 botocore
   ```

## Usage

### Running the Playbook

```bash
cd ansible/ziti-nonprod

# Recommended: Use the runner script (handles SSH key push and dynamic inventory)
./run-playbook.sh

# Or manually with dynamic inventory
ansible-playbook -i inventory/aws_ec2.yml playbook.yml
```

### Run Specific Tags

```bash
# Install binary only
./run-playbook.sh --tags install

# PKI only
./run-playbook.sh --tags pki

# Controller only
./run-playbook.sh --tags controller

# Credentials/Secrets Manager sync
./run-playbook.sh --tags credentials

# Services and policies
./run-playbook.sh --tags services,policies
```

### Rotate Admin Password

```bash
./run-playbook.sh -e "ziti_rotate_password=true"
```

## Identity Role Architecture

Ziti uses role attributes for scalable policy management. **Never reference identities directly in policies** - use role attributes instead.

### Standard Role Attributes

| Role | Purpose | Assigned To |
|------|---------|-------------|
| `users` | All human users | User identities |
| `developers` | Developer team members | Developer identities |
| `ssh-users` | Can dial SSH services | Users needing SSH access |
| `routers` | Edge routers that bind services | Router identities |
| `tunnelers` | Routers with tunneler enabled | Router identities |
| `ssh-services` | SSH service category | SSH services |

### Creating New Identities

```bash
# Use the create-identity playbook
ansible-playbook create-identity.yml \
  -e "identity_name=jane-dev" \
  -e "identity_roles=users,developers,ssh-users"

# Output: jane-dev.jwt
# User enrolls with: ziti edge enroll jane-dev.jwt
```

### Policy Structure

```
┌─────────────────────────────────────────────────────────────┐
│ Service Policies                                            │
├─────────────────────────────────────────────────────────────┤
│ ssh-bind:  #ssh-services → #routers (Bind)                  │
│ ssh-dial:  #ssh-services → #ssh-users (Dial)                │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ Edge Router Policies                                        │
├─────────────────────────────────────────────────────────────┤
│ users-to-routers: #all routers → #users                     │
└─────────────────────────────────────────────────────────────┘
```

## Credentials Management

### Admin Password

The admin password is stored in two places:
1. **AWS Secrets Manager**: `ziti/nonprod/admin-password` (primary)
2. **Filesystem**: `/opt/ziti/controller/.admin_password` (backup)

### Retrieve Admin Password

```bash
# From Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id ziti/nonprod/admin-password \
  --query SecretString --output text \
  --profile jfinlinson_admin

# Or from the instance
ssh ec2-user@<instance> "sudo cat /opt/ziti/controller/.admin_password"
```

### Login to Ziti CLI

```bash
# Get password from Secrets Manager
ZITI_PASS=$(aws secretsmanager get-secret-value \
  --secret-id ziti/nonprod/admin-password \
  --query SecretString --output text \
  --profile jfinlinson_admin)

# Login
ziti edge login https://ziti-nonprod.theraprac.com \
  --username admin \
  --password "$ZITI_PASS"
```

## What Gets Created

### Directory Structure on EC2

```
/opt/ziti/
├── bin/
│   └── ziti                    # Ziti binary (v1.6.9)
├── pki-ziti/                   # PKI hierarchy
│   ├── theraprac-root/         # Root CA
│   ├── theraprac-external-ica/ # External Intermediate
│   ├── theraprac-network-ica/  # Network Components ICA
│   ├── theraprac-edge-ica/     # Edge ICA (signs JWTs!)
│   └── theraprac-sign-ica/     # Signing ICA (enrollment)
├── db/
│   └── ctrl.db                 # Controller database
├── controller/
│   ├── controller.yaml         # Controller config
│   └── .admin_password         # Admin password (mode 600)
├── router/
│   ├── router.yaml             # Router config
│   ├── router.cert             # Router cert (from enrollment)
│   ├── router.key              # Router key
│   ├── router.server.cert      # Router server cert
│   └── ca-chain.cert           # CA chain
├── logs/
└── healthcheck/
    └── healthcheck.py          # Simple HTTP 200 responder
```

### Services

| Service | Port | Purpose |
|---------|------|---------|
| ziti-controller | 443, 6262 | Edge API + Control Plane |
| ziti-router | 8442 | Edge router for SDK clients |
| healthcheck | 8080 | NLB health check endpoint |

## Variables

Key variables in `roles/ziti/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `ziti_version` | `1.6.9` | Pinned Ziti version |
| `ziti_install_dir` | `/opt/ziti` | Base directory |
| `ziti_controller_port` | `443` | Edge API port |
| `ziti_router_edge_port` | `8442` | Router edge port |
| `ziti_public_endpoint` | `ziti-nonprod.theraprac.com` | Public DNS |
| `ziti_rotate_password` | `false` | Set to rotate admin password |
| `ziti_secrets_manager_path` | `ziti/nonprod/admin-password` | Secrets Manager path |

## Troubleshooting

### SSH Access (Break-Glass)

EC2 Instance Connect is available for emergency access:

```bash
# Get instance ID from Terraform
INSTANCE_ID=$(terraform -chdir=../../infra/phase4-ziti output -raw ziti_ec2_id)

# SSH via EICE
aws ec2-instance-connect ssh \
  --instance-id $INSTANCE_ID \
  --os-user ec2-user \
  --connection-type eice \
  --profile jfinlinson_admin
```

### Check Service Status

```bash
sudo systemctl status ziti-controller ziti-router healthcheck
sudo journalctl -u ziti-controller -f
sudo journalctl -u ziti-router -f
```

### Test Endpoints

```bash
# Health check (on instance)
curl http://localhost:8080/

# Controller API (from internet)
curl -sk https://ziti-nonprod.theraprac.com/edge/client/v1/version
```

### Router Not Online

```bash
# Check router logs
sudo journalctl -u ziti-router -n 100 --no-pager

# Verify enrollment files exist
ls -la /opt/ziti/router/

# Check router status in controller
ziti edge list edge-routers
```

## Disaster Recovery

### From AMI Backup

AMI snapshots are created periodically. To restore:

```bash
# Get latest AMI (check AWS Console or use aws ec2 describe-images)
# Update Terraform to use specific AMI if needed
# Apply Terraform
# Run Ansible to ensure configuration
```

### Fresh Install

1. Apply Terraform Phase 4 to create new EC2
2. Run Ansible playbook: `./run-playbook.sh`
3. Recreate user identities (JWTs expire, so users need new ones)

## Basic Server Provisioning

New servers can be provisioned with Ziti SSH access using the basic server pattern.

### Naming Convention

| Element | Example | Description |
|---------|---------|-------------|
| Name | `app` | Server purpose |
| Role | `mt` | Specific identifier/team |
| Tier | `app` | Subnet tier: app, db, or ziti |
| Environment | `nonprod` | Environment |
| **Full Name** | `app.mt.nonprod` | Combined identifier |
| **Subnet** | `private-app-nonprod-az1` | Derived from tier + env |
| **Internal DNS** | `app-mt-nonprod.theraprac-internal.com` | VPC-internal |
| **Ziti SSH** | `ssh.app.mt.nonprod.ziti` | Synthetic DNS for Ziti |

### Provisioning a New Server

```bash
# Run the provisioning script
./scripts/provision-basic-server.sh

# Prompts:
#   Name: app
#   Role: mt
#   Tier: app
#   Environment: nonprod
#   Instance type: t4g.micro
#   Architecture: arm64

# After completion, SSH via Ziti:
ssh jfinlinson@ssh.app.mt.nonprod.ziti
```

### How It Works

1. **Terraform** creates the EC2 instance with:
   - Private subnet (no public IP)
   - Security group allowing SSH from EICE and Ziti router only
   - `ansible` and `jfinlinson` users created via user_data
   - Private DNS record in `theraprac-internal.com`

2. **Ansible** registers the Ziti SSH service:
   - Creates `host.v1` config pointing to internal DNS
   - Creates `intercept.v1` config with synthetic DNS
   - Creates service with `#ssh-services` role attribute
   - Existing `ssh-bind` and `ssh-dial` policies auto-apply

### Verify joe-dev Has SSH Access

```bash
# Check joe-dev's role attributes
ziti edge list identities 'name="joe-dev"'

# If missing ssh-users, update:
ziti edge update identity joe-dev --role-attributes users,developers,ssh-users
```

### Files

| File | Purpose |
|------|---------|
| `infra/modules/basic-server/` | Reusable Terraform module |
| `infra/phase7-basic-server/` | Terraform config for basic servers |
| `scripts/provision-basic-server.sh` | Interactive provisioning script |
| `ansible/basic-server/playbook.yml` | Registers Ziti SSH service |

## Key Files Reference

| File | Purpose |
|------|---------|
| `defaults/main.yml` | All configurable variables |
| `tasks/install.yml` | Binary installation |
| `tasks/pki.yml` | PKI hierarchy creation |
| `tasks/controller.yml` | Controller config + edge init |
| `tasks/credentials.yml` | Password rotation + Secrets Manager |
| `tasks/router.yml` | Router config + enrollment |
| `tasks/ziti_services.yml` | Service definitions |
| `tasks/ziti_policies.yml` | Policy definitions |
| `create-identity.yml` | Standalone playbook for creating identities |
