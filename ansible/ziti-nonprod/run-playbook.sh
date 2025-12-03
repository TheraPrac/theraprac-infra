#!/bin/bash
# =============================================================================
# Ziti Ansible Playbook Runner
# =============================================================================
# Dynamically retrieves instance ID from Terraform and runs the playbook.
# Uses EC2 Instance Connect for secure SSH access.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../../infra/phase4-ziti"
SSH_KEY="$HOME/.ssh/id_ed25519_eice"
REGION="us-west-2"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd "$SCRIPT_DIR"

# Get instance ID from Terraform
echo -e "${GREEN}Retrieving instance ID from Terraform...${NC}"
if ! INSTANCE_ID=$(terraform -chdir="$INFRA_DIR" output -raw ziti_ec2_id 2>/dev/null); then
    echo -e "${RED}Failed to get instance ID from Terraform. Is phase4-ziti applied?${NC}"
    exit 1
fi

if ! AZ=$(terraform -chdir="$INFRA_DIR" output -raw ziti_availability_zone 2>/dev/null); then
    echo -e "${YELLOW}Could not get AZ from Terraform, defaulting to us-west-2a${NC}"
    AZ="us-west-2a"
fi

echo -e "${GREEN}Instance ID: ${INSTANCE_ID}${NC}"
echo -e "${GREEN}Availability Zone: ${AZ}${NC}"

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

# Export for dynamic inventory
export ZITI_INSTANCE_ID="$INSTANCE_ID"

echo -e "${GREEN}Running Ansible playbook...${NC}"
ansible-playbook -i inventory/aws_ec2.yml playbook.yml "$@"
