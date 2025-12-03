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

4. **SSH access** (via EC2 Instance Connect):
   ```bash
   aws ec2-instance-connect ssh --instance-id i-023506901dab49d56 \
     --os-user ec2-user --connection-type eice --profile jfinlinson_admin
   ```

## Usage

### Running the Playbook

```bash
cd ansible/ziti-nonprod

# Using static inventory (EC2 Instance Connect)
ansible-playbook -i inventory.yml playbook.yml
```

### Run Specific Tags

```bash
# Install binary only
ansible-playbook -i inventory.yml playbook.yml --tags install

# PKI only
ansible-playbook -i inventory.yml playbook.yml --tags pki

# Controller only
ansible-playbook -i inventory.yml playbook.yml --tags controller

# Router only
ansible-playbook -i inventory.yml playbook.yml --tags router
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

## PKI Architecture

The playbook creates a multi-level CA hierarchy required for Ziti v1.6+:

```
theraprac-root (Root CA)
└── theraprac-external-ica (External Intermediate)
    ├── theraprac-network-ica (Network Components)
    │   ├── network-server.cert  ← Controller fabric identity
    │   └── network-client.cert
    ├── theraprac-edge-ica (Edge)
    │   ├── edge-server.cert     ← Web identity (signs JWTs!)
    │   └── edge-client.cert
    └── theraprac-sign-ica (Signing)
        └── Used for enrollment signingCert
```

**Why this structure matters:**
- Router enrollment fetches the TLS cert from the NLB connection
- JWT is signed with the web identity key
- Router verifies JWT signature using the TLS cert's public key
- If ALB terminates TLS → different cert → signature mismatch → enrollment fails!

## Variables

Key variables in `roles/ziti/defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `ziti_version` | `1.6.9` | Pinned Ziti version |
| `ziti_install_dir` | `/opt/ziti` | Base directory |
| `ziti_controller_port` | `443` | Edge API port |
| `ziti_controller_ctrl_port` | `6262` | Control plane port |
| `ziti_router_edge_port` | `8442` | Router edge port |
| `ziti_healthcheck_port` | `8080` | Health check port |
| `ziti_public_endpoint` | `ziti-nonprod.theraprac.com` | Public DNS |

## Idempotency

The playbook is designed to be run multiple times safely:

- **Binary**: Only downloads if version mismatch
- **PKI**: Uses `creates:` guards, won't regenerate existing certs
- **Controller init**: Only runs if `ctrl.db` doesn't exist
- **Router enrollment**: Only runs if `router.cert` doesn't exist
- **Templates**: Only restart services on config changes

## Troubleshooting

### Check Service Status

```bash
# SSH to instance
aws ec2-instance-connect ssh --instance-id i-023506901dab49d56 \
  --os-user ec2-user --connection-type eice --profile jfinlinson_admin

# Check all services
sudo systemctl status ziti-controller ziti-router healthcheck

# View logs
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

### Get Admin Credentials

```bash
sudo cat /opt/ziti/controller/.admin_password
```

### Login to Ziti

```bash
# On the instance
ziti edge login https://ziti-nonprod.theraprac.com \
  --username admin \
  --password "$(sudo cat /opt/ziti/controller/.admin_password)"

# List identities
ziti edge list identities

# List routers
ziti edge list edge-routers
```

### Router Not Online

If the router shows as offline:

```bash
# Check router logs
sudo journalctl -u ziti-router -n 100 --no-pager

# Verify enrollment files exist
ls -la /opt/ziti/router/

# Re-enroll if needed (DESTRUCTIVE!)
ziti edge delete edge-router router-nonprod
ziti edge create edge-router router-nonprod -o /opt/ziti/router/router.jwt
ziti router enroll /opt/ziti/router/router.yaml --jwt /opt/ziti/router/router.jwt
sudo systemctl restart ziti-router
```

## Creating User Identities

```bash
# Login as admin
ziti edge login https://ziti-nonprod.theraprac.com --username admin --password <password>

# Create identity
ziti edge create identity user joe-dev -o joe-dev.jwt

# User enrolls on their machine
ziti edge enroll joe-dev.jwt -o ~/.config/ziti/identities/joe-dev.json
```

## Disaster Recovery

### From AMI Backup

An AMI snapshot was created: `ami-0c37299166e468048`

```bash
# Launch new instance from AMI
aws ec2 run-instances \
  --image-id ami-0c37299166e468048 \
  --instance-type t4g.micro \
  --subnet-id <private-ziti-subnet-id> \
  --iam-instance-profile Name=theraprac-ziti-controller-instance-profile \
  ...
```

### Fresh Install

1. Apply Terraform Phase 4 to create new EC2
2. Run Ansible playbook
3. Recreate user identities (JWTs expire, so users need new ones)

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `defaults/main.yml` | All configurable variables |
| `tasks/install.yml` | Binary installation |
| `tasks/pki.yml` | PKI hierarchy creation |
| `tasks/controller.yml` | Controller config + edge init |
| `tasks/router.yml` | Router config + enrollment |
| `tasks/systemd.yml` | Service management |
| `templates/controller.yaml.j2` | Controller config template |
| `templates/router.yaml.j2` | Router config template |
