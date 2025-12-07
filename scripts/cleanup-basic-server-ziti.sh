#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Cleanup Ziti Resources for Basic Server
# =============================================================================
# Removes Ziti resources (identities, services, configs, policies) for a
# basic server. This MUST be run BEFORE destroying the server with Terraform.
#
# IMPORTANT: This script connects directly to the Ziti controller API. The
# server does NOT need to be running or accessible. You can run this even
# if the server is already terminated (to clean up orphaned resources).
#
# Usage:
#   ./scripts/cleanup-basic-server-ziti.sh <name> <role> <environment>
#   ./scripts/cleanup-basic-server-ziti.sh app mt nonprod
#
# This script:
#   1. Derives server names from inputs
#   2. Runs Ansible playbook to clean up Ziti resources
#   3. Confirms cleanup before proceeding
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"

# Check arguments
if [ $# -lt 3 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo ""
    echo "Usage: $0 <name> <role> <environment>"
    echo ""
    echo "Examples:"
    echo "  $0 app mt nonprod"
    echo "  $0 api prod prod"
    exit 1
fi

NAME="$1"
ROLE="$2"
ENV="$3"

# Derive names
FULL_NAME="${NAME}.${ROLE}.${ENV}"
HYPHEN_NAME="${NAME}-${ROLE}-${ENV}"
ZITI_SSH="ssh.${FULL_NAME}.ziti"
ZITI_IDENTITY_NAME="${FULL_NAME}"

# Determine Ziti controller endpoint based on environment
if [ "$ENV" = "prod" ]; then
    ZITI_CONTROLLER_ENDPOINT="https://ziti-prod.theraprac.com"
elif [ "$ENV" = "nonprod" ] || [ "$ENV" = "dev" ] || [ "$ENV" = "test" ] || [ "$ENV" = "stage" ] || [ "$ENV" = "uat" ]; then
    # All non-production environments use the nonprod controller
    ZITI_CONTROLLER_ENDPOINT="https://ziti-nonprod.theraprac.com"
else
    echo -e "${RED}Error: Unknown environment '$ENV'. Must be one of: prod, nonprod, dev, test, stage, uat${NC}"
    exit 1
fi

echo -e "${BLUE}=== TheraPrac Ziti Cleanup for Basic Server ===${NC}"
echo ""
echo -e "Server: ${GREEN}${FULL_NAME}${NC}"
echo -e "Identity: ${GREEN}${ZITI_IDENTITY_NAME}${NC}"
echo -e "SSH Service: ${GREEN}${ZITI_SSH}${NC}"
echo -e "Controller: ${GREEN}${ZITI_CONTROLLER_ENDPOINT}${NC}"
echo ""

# Confirm cleanup
echo -e "${YELLOW}⚠ WARNING: This will delete the following Ziti resources:${NC}"
echo "  - Identity: $ZITI_IDENTITY_NAME"
echo "  - SSH Service: $ZITI_SSH"
echo "  - SSH Configs: ${ZITI_SSH}.host, ${ZITI_SSH}.intercept"
echo "  - SSH Bind Policy: ${ZITI_SSH}-bind"
echo ""
echo -e "${YELLOW}If HTTPS services were added, they will also be cleaned up.${NC}"
echo ""

read -p "Continue with cleanup? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

# Check if ziti CLI is available
if ! command -v ziti &> /dev/null; then
    echo -e "${RED}Error: ziti CLI not found in PATH${NC}"
    echo "Please install the Ziti CLI: https://openziti.io/docs/core-concepts/clients/cli"
    exit 1
fi

# Check if ansible-playbook is available
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: ansible-playbook not found in PATH${NC}"
    exit 1
fi

# Check for HTTPS services (optional - ask user)
echo ""
read -p "Were HTTPS services added to this server? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Web app domain (e.g., app-dev.theraprac.com): " APP_DOMAIN
    read -p "API domain (e.g., api-dev.theraprac.com): " API_DOMAIN
fi

# Build ansible-playbook command
ANSIBLE_CMD="ansible-playbook -i inventory/server-eice.yml cleanup-ziti.yml"
ANSIBLE_CMD="$ANSIBLE_CMD -e \"server_name=${FULL_NAME}\""
ANSIBLE_CMD="$ANSIBLE_CMD -e \"ziti_ssh_name=${ZITI_SSH}\""
ANSIBLE_CMD="$ANSIBLE_CMD -e \"ziti_identity_name=${ZITI_IDENTITY_NAME}\""
ANSIBLE_CMD="$ANSIBLE_CMD -e \"ziti_controller_endpoint=${ZITI_CONTROLLER_ENDPOINT}\""

if [ -n "$APP_DOMAIN" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD -e \"app_domain=${APP_DOMAIN}\""
fi

if [ -n "$API_DOMAIN" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD -e \"api_domain=${API_DOMAIN}\""
fi

# Run cleanup
echo ""
echo -e "${CYAN}Running Ziti cleanup...${NC}"
cd "$ANSIBLE_DIR"
eval "$ANSIBLE_CMD"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Ziti cleanup complete!${NC}"
    echo ""
    echo -e "${GREEN}Safe to destroy server with Terraform:${NC}"
    echo "  cd infra/phase7-basic-server"
    echo "  terraform destroy -var=\"name=${NAME}\" -var=\"role=${ROLE}\" -var=\"tier=app\" -var=\"environment=${ENV}\""
else
    echo ""
    echo -e "${RED}❌ Ziti cleanup failed${NC}"
    echo "Please review the errors above before destroying the server."
    exit 1
fi

