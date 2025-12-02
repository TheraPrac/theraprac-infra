# TheraPrac Ziti Nonprod Ansible Playbook

This playbook installs and configures OpenZiti controller + router on the nonprod Ziti EC2 instance.

## Prerequisites

1. **Terraform must be applied first** - The Ziti EC2 instance must exist before running this playbook.
   ```bash
   cd ../../infra/phase4-ziti
   terraform apply
   ```

2. **AWS CLI configured** - You need valid AWS credentials with SSM permissions.
   ```bash
   aws sso login --profile jfinlinson_admin
   ```

3. **Ansible AWS collection installed**:
   ```bash
   ansible-galaxy collection install amazon.aws
   pip install boto3 botocore
   ```

4. **Session Manager plugin installed** (for SSM connections):
   - macOS: `brew install session-manager-plugin`
   - See: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

## Directory Structure

```
ansible/ziti-nonprod/
├── inventory/
│   └── aws_ssm.yml          # Dynamic SSM inventory
├── playbook.yml             # Main playbook
├── roles/
│   └── ziti/
│       ├── tasks/
│       │   ├── install.yml      # Download and install Ziti binaries
│       │   ├── pki.yml          # Generate PKI certificates
│       │   ├── controller.yml   # Configure Ziti controller
│       │   ├── router.yml       # Configure Ziti router
│       │   ├── systemd.yml      # Create systemd services
│       │   └── healthcheck.yml  # Set up health check endpoint
│       ├── templates/
│       │   ├── controller.yaml.j2
│       │   ├── router.yaml.j2
│       │   ├── ziti-controller.service.j2
│       │   ├── ziti-router.service.j2
│       │   └── healthcheck.service.j2
│       ├── handlers/
│       │   └── main.yml
│       └── defaults/
│           └── main.yml
└── README.md
```

## Usage

### Run the full playbook

```bash
cd ansible/ziti-nonprod
ansible-playbook -i inventory/aws_ssm.yml playbook.yml
```

### Run specific tasks with tags

```bash
# Only install Ziti binaries
ansible-playbook -i inventory/aws_ssm.yml playbook.yml --tags install

# Only configure PKI
ansible-playbook -i inventory/aws_ssm.yml playbook.yml --tags pki

# Only restart services
ansible-playbook -i inventory/aws_ssm.yml playbook.yml --tags services
```

### Check mode (dry run)

```bash
ansible-playbook -i inventory/aws_ssm.yml playbook.yml --check
```

## What This Playbook Does

1. **install.yml** - Downloads and installs OpenZiti binaries from GitHub releases
2. **pki.yml** - Generates PKI certificates (root CA, intermediate CA, server certs)
3. **controller.yml** - Configures and initializes the Ziti controller
4. **router.yml** - Configures and enrolls the Ziti edge router
5. **systemd.yml** - Creates systemd service units for controller and router
6. **healthcheck.yml** - Sets up a simple health check endpoint on port 8080 for ALB

## Architecture

```
Internet
    │
    ▼
┌─────────────────┐
│  ALB (HTTPS)    │  ziti-nonprod.theraprac.com
│  Port 443       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Ziti EC2       │  private-ziti-nonprod-az1
│  - Controller   │  Port 443 (Ziti API)
│  - Router       │  Port 8080 (Health check)
└─────────────────┘
```

- **ALB terminates TLS** using ACM certificate
- **Ziti controller** listens on port 443 (internal TLS)
- **Health check** runs on port 8080 (HTTP) for ALB target health

## Variables

Key variables in `roles/ziti/defaults/main.yml`:

| Variable | Description | Default |
|----------|-------------|---------|
| `ziti_version` | OpenZiti version to install | `1.1.3` |
| `ziti_home` | Installation directory | `/opt/ziti` |
| `ziti_domain` | Public domain name | `ziti-nonprod.theraprac.com` |
| `ziti_controller_port` | Controller API port | `443` |
| `ziti_health_port` | Health check port | `8080` |

## Troubleshooting

### Cannot connect via SSM

1. Verify the EC2 instance has the correct IAM role attached
2. Check that the SSM agent is running: `systemctl status amazon-ssm-agent`
3. Ensure the instance can reach SSM endpoints via NAT Gateway

### Health check failing

1. SSH into the instance and check service status:
   ```bash
   systemctl status ziti-healthcheck
   curl http://localhost:8080/health
   ```

2. Check the health check logs:
   ```bash
   journalctl -u ziti-healthcheck -f
   ```

### Controller not starting

1. Check controller logs:
   ```bash
   journalctl -u ziti-controller -f
   ```

2. Verify PKI certificates are correctly generated:
   ```bash
   ls -la /opt/ziti/pki/
   ```

## Security Notes

- Admin credentials are stored in `/opt/ziti/controller/admin-credentials.txt` (mode 0600)
- All PKI private keys are stored with mode 0600
- The health check endpoint does NOT expose sensitive information
