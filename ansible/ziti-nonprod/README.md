# TheraPrac Ziti Nonprod Deployment

This directory contains Ansible playbooks and roles for deploying OpenZiti controller and router on AWS EC2 for the TheraPrac nonprod environment.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS (443)
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    APPLICATION LOAD BALANCER                            │
│                   (ziti-nonprod.theraprac.com)                          │
│                    ACM Certificate (TLS 1.2+)                           │
│                    Public Subnets (az1/az2/az3)                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS (443) - internal
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        ZITI EC2 INSTANCE                                │
│                     (private-ziti-nonprod-az1)                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Ziti Controller (:443)                                         │    │
│  │  - Manages identities, services, policies                       │    │
│  │  - Edge API for management                                      │    │
│  │  - Client API for SDK connections                               │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Ziti Router (:6262)                                            │    │
│  │  - Edge router for client connections                           │    │
│  │  - Tunneler for service hosting                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  Health Check Server (:8080)                                    │    │
│  │  - /health endpoint for ALB                                     │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ NAT Instance
                                    ▼
                          ┌─────────────────┐
                          │  AWS APIs       │
                          │  (Secrets, Logs)│
                          └─────────────────┘
```

### Key Components

| Component | Purpose |
|-----------|---------|
| **ALB** | TLS termination, public endpoint |
| **Ziti Controller** | Identity & policy management |
| **Ziti Router** | Overlay network data plane |
| **NAT Instance** | Outbound internet for AWS APIs |
| **S3 Gateway** | Private S3 access |

### Network Flow

1. **External clients** connect via ALB → `ziti-nonprod.theraprac.com:443`
2. **ALB terminates TLS** using ACM certificate
3. **Forwards to EC2** on internal port 443
4. **Ziti handles overlay** encryption end-to-end
5. **Outbound traffic** goes through NAT instance

---

## Prerequisites

- Ansible 2.9+
- SSH access to EC2 instance (via bastion or SSM)
- Terraform Phase 4 applied

## Running the Playbook

### 1. Get the EC2 Private IP

```bash
cd ../infra/phase4-ziti
terraform output ziti_instance_private_ip
```

### 2. Set Environment Variables

```bash
export ZITI_HOST=10.20.30.x  # Replace with actual IP
export SSH_KEY_PATH=~/.ssh/theraprac-nonprod.pem
```

### 3. Run the Playbook

```bash
cd ansible/ziti-nonprod
ansible-playbook -i inventory.yml playbook.yml
```

Or with explicit host:

```bash
ansible-playbook -i "${ZITI_HOST}," -u ec2-user playbook.yml
```

---

## Identity Management

### Creating a New Identity

```bash
# SSH to Ziti instance
ssh -i ~/.ssh/theraprac-nonprod.pem ec2-user@<private-ip>

# Login to Ziti CLI
sudo ziti edge login https://localhost:443 -u admin -p <password>

# Create a user identity
sudo ziti edge create identity user developer-joe \
  --role-attributes developers \
  --jwt-output-file /opt/ziti/enrollments/developer-joe.jwt

# Create a service identity (for apps)
sudo ziti edge create identity device app-server-1 \
  --role-attributes app-servers \
  --jwt-output-file /opt/ziti/enrollments/app-server-1.jwt
```

### Viewing Identities

```bash
sudo ziti edge list identities
```

### Deleting an Identity

```bash
sudo ziti edge delete identity developer-joe
```

### Updating Identity Roles

```bash
# Add role
sudo ziti edge update identity developer-joe --role-attributes developers,admins

# Remove role (set new list without the role)
sudo ziti edge update identity developer-joe --role-attributes developers
```

---

## Developer Enrollment (Desktop Client)

### Step 1: Download Ziti Desktop Edge

- **macOS**: [Download DMG](https://github.com/openziti/desktop-edge-macos/releases)
- **Windows**: [Download MSI](https://github.com/openziti/desktop-edge-win/releases)
- **Linux**: [Download DEB/RPM](https://github.com/openziti/ziti-tunnel-sdk-c/releases)

### Step 2: Get Your Enrollment JWT

1. Request JWT from admin (or create yourself if authorized)
2. Admin provides `.jwt` file or shares content

### Step 3: Enroll in Desktop Client

**macOS/Windows:**
1. Open Ziti Desktop Edge
2. Click "Add Identity"
3. Select the `.jwt` file
4. Identity enrolls automatically

**Linux CLI:**
```bash
ziti-edge-tunnel enroll --jwt /path/to/identity.jwt --identity /path/to/identity.json
ziti-edge-tunnel run --identity /path/to/identity.json
```

### Step 4: Verify Connection

1. Check Desktop Edge shows "Connected"
2. Verify green status indicator
3. Test accessing a Ziti service:

```bash
# If configured, access internal services via Ziti DNS
curl https://api.theraprac.ziti/health
```

---

## Identity Rotation & Revocation

### Rotating an Identity (Re-enrollment)

```bash
# Generate new JWT for existing identity
sudo ziti edge create identity-reissue developer-joe \
  --jwt-output-file /opt/ziti/enrollments/developer-joe-new.jwt

# User enrolls with new JWT (old identity still works until they re-enroll)
```

### Revoking Access Immediately

```bash
# Delete identity (immediate disconnect)
sudo ziti edge delete identity developer-joe

# Or disable without deleting
sudo ziti edge update identity developer-joe --disabled
```

### Emergency Revocation

```bash
# Revoke all sessions for an identity
sudo ziti edge delete identity-sessions developer-joe
```

---

## How Tunneling Works for TheraPrac

### Application Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Browser    │────▶│  Next.js App │────▶│   Go API     │────▶│   Postgres   │
│              │     │ (Ziti SDK)   │     │ (Ziti SDK)   │     │   (Ziti)     │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                            │                    │                    │
                            └────────────────────┴────────────────────┘
                                        │
                                        ▼
                              ┌──────────────────┐
                              │   Ziti Network   │
                              │  (Zero Trust)    │
                              └──────────────────┘
```

### Developer Access Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Developer   │────▶│ Ziti Desktop │────▶│  VPC Private │
│  Laptop      │     │    Edge      │     │  Resources   │
└──────────────┘     └──────────────┘     └──────────────┘
        │                    │
        │                    ▼
        │          ┌──────────────────┐
        │          │ Ziti Router      │
        │          │ (us-west-2)      │
        │          └──────────────────┘
        │                    │
        └────────────────────┘
            Encrypted Overlay
```

### Key Concepts

1. **Zero Trust**: No implicit network trust
2. **Identity-based**: Access tied to cryptographic identity
3. **Application-embedded**: SDKs in apps, no VPN needed
4. **End-to-end encryption**: Even within VPC

---

## Health Checks

### ALB Health Check Endpoint

The Ziti instance runs a health check server on port 8080:

| Endpoint | Purpose | Response |
|----------|---------|----------|
| `/health` | ALB health check | `{"status": "healthy", "controller": "running", "router": "running"}` |
| `/healthz` | Kubernetes-style | Same as `/health` |
| `/ready` | Readiness check | `{"ready": true}` |

### Checking Health Manually

```bash
# From the Ziti instance
curl http://localhost:8080/health

# Check service status
sudo systemctl status ziti-controller
sudo systemctl status ziti-router
sudo systemctl status ziti-healthcheck
```

### Logs

```bash
# Controller logs
sudo tail -f /var/log/ziti/controller.log

# Router logs
sudo tail -f /var/log/ziti/router.log

# Health check logs
sudo tail -f /var/log/ziti/healthcheck.log

# Or via journalctl
sudo journalctl -u ziti-controller -f
sudo journalctl -u ziti-router -f
```

---

## Troubleshooting

### Controller Won't Start

```bash
# Check config syntax
sudo /opt/ziti/bin/ziti controller validate /opt/ziti/controller/controller.yaml

# Check permissions
ls -la /opt/ziti/

# Check logs
sudo journalctl -u ziti-controller -n 50
```

### Router Won't Enroll

```bash
# Ensure controller is running
curl -k https://localhost:443/edge/client/v1/version

# Check enrollment JWT
cat /opt/ziti/enrollments/router.jwt | base64 -d | jq .

# Re-enroll
sudo /opt/ziti/bin/ziti router enroll /opt/ziti/router/router.yaml \
  --jwt /opt/ziti/enrollments/router.jwt
```

### ALB Health Check Failing

```bash
# Verify health check server
curl http://localhost:8080/health

# Check security group allows ALB → EC2 on 443
# Check target group health in AWS Console
```

---

## Security Notes

- **Admin password**: Stored in `/opt/ziti/controller/admin-credentials.txt`
- **PKI**: All certs in `/opt/ziti/pki/` with restricted permissions
- **SSH**: Password auth disabled, key-only
- **fail2ban**: Enabled for SSH protection
- **Outbound**: Restricted to VPC + NAT only

---

## File Locations

| Path | Description |
|------|-------------|
| `/opt/ziti/` | Ziti home directory |
| `/opt/ziti/bin/` | Ziti binaries |
| `/opt/ziti/controller/` | Controller config & data |
| `/opt/ziti/router/` | Router config & certs |
| `/opt/ziti/pki/` | PKI certificates |
| `/opt/ziti/enrollments/` | Enrollment JWTs |
| `/var/log/ziti/` | Log files |

