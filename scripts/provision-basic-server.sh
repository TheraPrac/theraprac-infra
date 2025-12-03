#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Basic Server Provisioning Script
# =============================================================================
# Creates a private EC2 instance accessible via Ziti SSH.
#
# Usage:
#   ./scripts/provision-basic-server.sh
#
# The script will prompt for:
#   - Name: Server purpose (e.g., "app")
#   - Role: Specific identifier (e.g., "mt")
#   - Tier: Subnet tier (app, db, ziti)
#   - Environment: nonprod or prod
#   - Instance type: t4g.micro, t4g.small, etc.
#   - Architecture: arm64 or x86_64
#
# After Terraform creates the instance, Ansible registers the Ziti SSH service.
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/phase7-basic-server"
ZITI_TF_DIR="$REPO_ROOT/infra/phase4-ziti"
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"

# =============================================================================
# Helper Functions
# =============================================================================

prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local value

    if [ -n "$default_value" ]; then
        read -p "$prompt_text [$default_value]: " value
        value="${value:-$default_value}"
    else
        while [ -z "$value" ]; do
            read -p "$prompt_text: " value
            if [ -z "$value" ]; then
                echo -e "${RED}This field is required.${NC}"
            fi
        done
    fi

    eval "$var_name=\"$value\""
}

prompt_choice() {
    local var_name="$1"
    local prompt_text="$2"
    local options="$3"
    local default_value="$4"
    local value

    echo -e "${BLUE}$prompt_text${NC}"
    echo "  Options: $options"
    
    if [ -n "$default_value" ]; then
        read -p "  Choice [$default_value]: " value
        value="${value:-$default_value}"
    else
        while [ -z "$value" ]; do
            read -p "  Choice: " value
        done
    fi

    eval "$var_name=\"$value\""
}

# =============================================================================
# Load SSH Keys from phase4-ziti terraform.tfvars
# =============================================================================

load_ssh_keys() {
    local tfvars_file="$ZITI_TF_DIR/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        echo -e "${RED}Error: SSH keys file not found: $tfvars_file${NC}"
        echo "Please ensure phase4-ziti has been configured with terraform.tfvars"
        exit 1
    fi

    # Extract SSH keys from tfvars
    SSH_KEY_ANSIBLE=$(grep '^ssh_key_ansible' "$tfvars_file" | sed 's/.*= *"\(.*\)"/\1/')
    SSH_KEY_JFINLINSON=$(grep '^ssh_key_jfinlinson' "$tfvars_file" | sed 's/.*= *"\(.*\)"/\1/')

    if [ -z "$SSH_KEY_ANSIBLE" ] || [ -z "$SSH_KEY_JFINLINSON" ]; then
        echo -e "${RED}Error: Could not load SSH keys from $tfvars_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Loaded SSH keys from phase4-ziti${NC}"
}

# =============================================================================
# Main Script
# =============================================================================

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       TheraPrac Basic Server Provisioning                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${YELLOW}AWS session expired or not configured.${NC}"
    echo "Please run: aws sso login --profile jfinlinson_admin"
    exit 1
fi

# Load SSH keys
load_ssh_keys

echo ""
echo -e "${BLUE}=== Server Configuration ===${NC}"
echo ""

# Prompt for inputs
prompt NAME "Name (server purpose, e.g., 'app')" ""
prompt ROLE "Role (identifier, e.g., 'mt')" ""
prompt_choice TIER "Tier (subnet)" "app, db, ziti" "app"
prompt_choice ENV "Environment" "nonprod, prod" "nonprod"
prompt INSTANCE_TYPE "Instance type" "t4g.micro"
prompt_choice ARCH "Architecture" "arm64, x86_64" "arm64"

# Derive names
FULL_NAME="${NAME}.${ROLE}.${ENV}"
HYPHEN_NAME="${NAME}-${ROLE}-${ENV}"
SUBNET="private-${TIER}-${ENV}-az1"
INTERNAL_DNS="${HYPHEN_NAME}.theraprac-internal.com"
ZITI_SSH="ssh.${FULL_NAME}.ziti"

echo ""
echo -e "${BLUE}=== Configuration Summary ===${NC}"
echo ""
echo -e "  Full Name:     ${GREEN}${FULL_NAME}${NC}"
echo -e "  Tier:          ${TIER}"
echo -e "  Subnet:        ${SUBNET}"
echo -e "  Instance Type: ${INSTANCE_TYPE}"
echo -e "  Architecture:  ${ARCH}"
echo ""
echo -e "  Internal DNS:  ${GREEN}${INTERNAL_DNS}${NC}"
echo -e "  Ziti SSH:      ${GREEN}${ZITI_SSH}${NC}"
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# =============================================================================
# Terraform
# =============================================================================

echo ""
echo -e "${BLUE}=== Running Terraform ===${NC}"
echo ""

cd "$TF_DIR"

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
fi

# Plan
echo -e "${YELLOW}Planning...${NC}"
terraform plan \
    -var="name=$NAME" \
    -var="role=$ROLE" \
    -var="tier=$TIER" \
    -var="environment=$ENV" \
    -var="instance_type=$INSTANCE_TYPE" \
    -var="arch=$ARCH" \
    -var="ssh_key_ansible=$SSH_KEY_ANSIBLE" \
    -var="ssh_key_jfinlinson=$SSH_KEY_JFINLINSON" \
    -out=tfplan

echo ""
read -p "Apply this plan? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Apply
echo -e "${YELLOW}Applying...${NC}"
terraform apply tfplan

# Capture outputs
INSTANCE_ID=$(terraform output -raw instance_id)
SERVER_INTERNAL_DNS=$(terraform output -raw internal_dns)
SERVER_ZITI_SSH=$(terraform output -raw ziti_ssh)

echo ""
echo -e "${GREEN}✓ Terraform complete${NC}"
echo "  Instance ID: $INSTANCE_ID"

# =============================================================================
# Ansible - Register Ziti SSH Service
# =============================================================================

echo ""
echo -e "${BLUE}=== Registering Ziti SSH Service ===${NC}"
echo ""

# Check if Ziti tunnel is available
if nc -z -w 2 ssh.ziti-nonprod.ziti 22 2>/dev/null || \
   timeout 2 bash -c "echo >/dev/tcp/ssh.ziti-nonprod.ziti/22" 2>/dev/null; then
    echo -e "${GREEN}✓ Ziti tunnel active${NC}"
    ANSIBLE_INVENTORY="$ANSIBLE_DIR/inventory/ziti.yml"
else
    echo -e "${YELLOW}⚠ Ziti tunnel not available, using EICE${NC}"
    ANSIBLE_INVENTORY="$ANSIBLE_DIR/inventory/eice.yml"
fi

cd "$ANSIBLE_DIR"

ansible-playbook playbook.yml \
    -i "$ANSIBLE_INVENTORY" \
    -e "server_name=$FULL_NAME" \
    -e "server_internal_dns=$SERVER_INTERNAL_DNS" \
    -e "ziti_ssh_name=$SERVER_ZITI_SSH"

# =============================================================================
# Done
# =============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Provisioning Complete!                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Server:       ${FULL_NAME}"
echo -e "  Instance ID:  ${INSTANCE_ID}"
echo -e "  Internal DNS: ${SERVER_INTERNAL_DNS}"
echo ""
echo -e "  ${BLUE}SSH via Ziti (requires ZDE running):${NC}"
echo -e "    ssh jfinlinson@${SERVER_ZITI_SSH}"
echo ""
echo -e "  ${YELLOW}SSH via EICE (break-glass):${NC}"
echo -e "    aws ec2-instance-connect ssh --instance-id ${INSTANCE_ID} --os-user jfinlinson --connection-type eice"
echo ""

