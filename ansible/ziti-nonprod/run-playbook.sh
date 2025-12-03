#!/bin/bash
# =============================================================================
# Ziti Ansible Playbook Runner
# =============================================================================
# Pushes SSH key to EC2 via Instance Connect and runs the playbook.
# The SSH key is only valid for 60 seconds, so this script handles the refresh.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_ID="i-023506901dab49d56"
AZ="us-west-2a"
REGION="us-west-2"
SSH_KEY="$HOME/.ssh/id_ed25519_eice"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$SCRIPT_DIR"

# Generate SSH key if it doesn't exist
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${YELLOW}Generating SSH key...${NC}"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "eice-ansible"
fi

echo -e "${GREEN}Pushing SSH key to EC2 instance...${NC}"
aws ec2-instance-connect send-ssh-public-key \
    --instance-id "$INSTANCE_ID" \
    --instance-os-user ec2-user \
    --ssh-public-key "file://${SSH_KEY}.pub" \
    --region "$REGION" \
    --availability-zone "$AZ"

echo -e "${GREEN}Running Ansible playbook...${NC}"
ansible-playbook -i inventory/hosts.ini playbook.yml "$@"
