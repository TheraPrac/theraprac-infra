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
