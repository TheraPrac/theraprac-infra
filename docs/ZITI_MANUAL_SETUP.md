# Ziti Manual Setup Documentation

This document captures all manual CLI work performed to get Ziti working. This should eventually be automated in Ansible.

## Backup

**AMI Snapshot**: `ami-0c37299166e468048`
- Created: 2025-12-03
- Description: Working Ziti controller+router with enrolled joe-dev identity
- Instance: i-023506901dab49d56

---

## Current State Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Controller | ✅ Running | v1.6.9, systemd enabled |
| Router | ✅ Running, Online | enrolled as `router-nonprod` |
| Admin Password | `AmZPCzREbR1sVwoGZWMcPePt` | stored in `/opt/ziti/controller/.admin_password` |
| Identities | `Default Admin`, `joe-dev` | joe-dev is enrolled |
| Services | None | SSH service not yet created |
| Service Policies | None | |

---

## PKI Structure

The working PKI is in `/opt/ziti/pki-ziti/` with a multi-level CA hierarchy:

```
theraprac-root/                          # Root CA
├── certs/theraprac-root.cert
└── keys/theraprac-root.key

theraprac-external-ica/                  # External Intermediate CA
├── certs/theraprac-external-ica.cert
└── keys/theraprac-external-ica.key

theraprac-network-ica/                   # Network Components ICA
├── certs/
│   ├── theraprac-network-ica.cert
│   ├── theraprac-network-ica.chain.pem
│   ├── network-client.cert
│   ├── network-client.chain.pem
│   ├── network-server.cert
│   └── network-server.chain.pem
├── keys/
│   ├── theraprac-network-ica.key
│   ├── network-components.key          # Shared key for client/server
│   ├── network-client.key
│   └── network-server.key
├── cas.pem
└── cas-full.pem                         # Full CA chain

theraprac-edge-ica/                      # Edge ICA (web identity)
├── certs/
│   ├── theraprac-edge-ica.cert
│   ├── theraprac-edge-ica.chain.pem
│   ├── edge-client.cert
│   ├── edge-client.chain.pem
│   ├── edge-server.cert
│   └── edge-server.chain.pem
├── keys/
│   ├── theraprac-edge-ica.key
│   ├── edge-components.key
│   ├── edge-client.key
│   └── edge-server.key
├── edge.cas.pem
└── edge.cas-full.pem

theraprac-sign-ica/                      # Signing ICA (enrollment)
├── certs/
│   ├── theraprac-sign-ica.cert
│   └── theraprac-sign-ica.chain.pem
└── keys/theraprac-sign-ica.key
```

---

## Manual Steps Performed

### 1. Upgrade Ziti Binary (from v1.1.3 to v1.6.9)

```bash
# Download latest ARM64 binary
cd /tmp
curl -sL https://github.com/openziti/ziti/releases/download/v1.6.9/ziti-linux-arm64-v1.6.9.tar.gz -o ziti.tar.gz
tar xzf ziti.tar.gz

# Install
sudo mv ziti /opt/ziti/bin/
sudo chmod +x /opt/ziti/bin/ziti

# Verify
/opt/ziti/bin/ziti version
```

### 2. Create PKI with Multi-Level CA Hierarchy

```bash
cd /opt/ziti
PKI_ROOT="/opt/ziti/pki-ziti"

# Create Root CA
ziti pki create ca --pki-root "$PKI_ROOT" --ca-name theraprac-root

# Create External Intermediate CA (signed by root)
ziti pki create intermediate --pki-root "$PKI_ROOT" \
  --ca-name theraprac-root \
  --intermediate-name theraprac-external-ica

# Create Network Components ICA (for controller fabric identity)
ziti pki create intermediate --pki-root "$PKI_ROOT" \
  --ca-name theraprac-external-ica \
  --intermediate-name theraprac-network-ica

# Create Edge ICA (for web/edge API identity)
ziti pki create intermediate --pki-root "$PKI_ROOT" \
  --ca-name theraprac-external-ica \
  --intermediate-name theraprac-edge-ica

# Create Signing ICA (for enrollment signingCert)
ziti pki create intermediate --pki-root "$PKI_ROOT" \
  --ca-name theraprac-external-ica \
  --intermediate-name theraprac-sign-ica

# Create Network server/client certs
ziti pki create server --pki-root "$PKI_ROOT" \
  --ca-name theraprac-network-ica \
  --server-name network-server \
  --dns "localhost,ziti-nonprod.theraprac.com" \
  --ip "127.0.0.1"

ziti pki create client --pki-root "$PKI_ROOT" \
  --ca-name theraprac-network-ica \
  --client-name network-client

# Create Edge server/client certs
ziti pki create server --pki-root "$PKI_ROOT" \
  --ca-name theraprac-edge-ica \
  --server-name edge-server \
  --dns "localhost,ziti-nonprod.theraprac.com" \
  --ip "127.0.0.1"

ziti pki create client --pki-root "$PKI_ROOT" \
  --ca-name theraprac-edge-ica \
  --client-name edge-client

# Create CA chain files
cat "$PKI_ROOT/theraprac-network-ica/certs/theraprac-network-ica.chain.pem" \
    "$PKI_ROOT/theraprac-external-ica/certs/theraprac-external-ica.chain.pem" \
    "$PKI_ROOT/theraprac-root/certs/theraprac-root.cert" \
    > "$PKI_ROOT/theraprac-network-ica/cas-full.pem"

cat "$PKI_ROOT/theraprac-edge-ica/certs/theraprac-edge-ica.chain.pem" \
    "$PKI_ROOT/theraprac-external-ica/certs/theraprac-external-ica.chain.pem" \
    "$PKI_ROOT/theraprac-root/certs/theraprac-root.cert" \
    > "$PKI_ROOT/theraprac-edge-ica/edge.cas-full.pem"
```

### 3. Create Controller Configuration

The controller config at `/opt/ziti/controller/controller.yaml` uses:

**Identity (fabric/ctrl):**
```yaml
identity:
  cert:        "/opt/ziti/pki-ziti/theraprac-network-ica/certs/network-client.cert"
  server_cert: "/opt/ziti/pki-ziti/theraprac-network-ica/certs/network-server.chain.pem"
  key:         "/opt/ziti/pki-ziti/theraprac-network-ica/keys/network-components.key"
  ca:          "/opt/ziti/pki-ziti/theraprac-network-ica/cas-full.pem"
```

**Signing Cert (enrollment):**
```yaml
edge:
  enrollment:
    signingCert:
      cert: /opt/ziti/pki-ziti/theraprac-sign-ica/certs/theraprac-sign-ica.chain.pem
      key:  /opt/ziti/pki-ziti/theraprac-sign-ica/keys/theraprac-sign-ica.key
```

**Web Identity (edge API):**
```yaml
web:
  - name: client-management
    identity:
      ca:          "/opt/ziti/pki-ziti/theraprac-edge-ica/edge.cas-full.pem"
      key:         "/opt/ziti/pki-ziti/theraprac-edge-ica/keys/edge-components.key"
      server_cert: "/opt/ziti/pki-ziti/theraprac-edge-ica/certs/edge-server.chain.pem"
      cert:        "/opt/ziti/pki-ziti/theraprac-edge-ica/certs/edge-client.cert"
```

### 4. Initialize Controller Edge Database

```bash
# Start controller first time to create database
sudo systemctl start ziti-controller

# Initialize edge (creates admin identity, sets password)
sudo /opt/ziti/bin/ziti controller edge init /opt/ziti/controller/controller.yaml \
  --username admin \
  --password "$(cat /opt/ziti/controller/.admin_password)"
```

### 5. Create and Enroll Router

```bash
# Login to controller
ziti edge login https://ziti-nonprod.theraprac.com --username admin --password "$(cat /opt/ziti/controller/.admin_password)"

# Create edge router identity
ziti edge create edge-router router-nonprod -o /opt/ziti/router/router.jwt

# Enroll router (generates certs in /opt/ziti/router/)
ziti router enroll /opt/ziti/router/router.yaml --jwt /opt/ziti/router/router.jwt

# Start router
sudo systemctl start ziti-router
sudo systemctl enable ziti-router
```

### 6. Create User Identity

```bash
# Create joe-dev identity
ziti edge create identity joe-dev -o /home/ec2-user/joe-dev.jwt

# User enrolls on their machine:
# ziti edge enroll joe-dev.jwt -o ~/.config/ziti/identities/joe-dev.json
```

---

## Files to Preserve

If rebuilding, these files/directories contain critical state:

| Path | Purpose |
|------|---------|
| `/opt/ziti/pki-ziti/` | All PKI certificates and keys |
| `/opt/ziti/controller/controller.yaml` | Controller configuration |
| `/opt/ziti/controller/.admin_password` | Admin password |
| `/opt/ziti/db/ctrl.db` | Controller database (identities, enrollments, etc.) |
| `/opt/ziti/router/router.yaml` | Router configuration |
| `/opt/ziti/router/router.cert` | Router certificate (from enrollment) |
| `/opt/ziti/router/router.key` | Router private key |
| `/opt/ziti/router/router.server.cert` | Router server certificate |
| `/opt/ziti/router/ca-chain.cert` | Router CA chain |

---

## Systemd Services

All services are configured with:
- `Restart=always`
- `RestartSec=5`
- Proper ordering (router waits for controller)

```bash
# Enable on boot
sudo systemctl enable ziti-controller
sudo systemctl enable ziti-router
sudo systemctl enable healthcheck

# Check status
sudo systemctl status ziti-controller
sudo systemctl status ziti-router
sudo systemctl status healthcheck
```

---

## Critical Discovery: ALB vs NLB

The router enrollment was failing with "token signature is invalid" because:

1. AWS ALB terminates TLS with ACM certificate
2. Router fetches TLS cert from connection to verify JWT
3. Router got ACM cert (not controller's cert)
4. JWT was signed with controller's web identity key
5. **Signature mismatch!**

**Solution**: Changed from ALB to NLB with TCP passthrough. Now the controller presents its own TLS certificate directly.

---

## What Ansible Should Automate

To make this reproducible, Ansible needs to:

1. ✅ Install Ziti binary (already done)
2. ❌ Create full PKI hierarchy using `ziti pki` commands
3. ❌ Generate controller.yaml with correct PKI paths
4. ❌ Run `ziti controller edge init`
5. ❌ Create router identity and enroll
6. ❌ Store admin password securely
7. ✅ Create systemd services (already done)
8. ✅ Health check (already done)


