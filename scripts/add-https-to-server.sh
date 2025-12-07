#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Add HTTPS to Server
# =============================================================================
# Adds nginx, TLS certificates, and Ziti HTTPS services to an existing server.
#
# This script:
#   1. Validates AWS credentials
#   2. Checks/applies Terraform IAM (Route53 permissions)
#   3. Runs Ansible add-https.yml playbook
#
# Prerequisites:
#   - Server already provisioned via provision-basic-server.sh
#   - ziti-edge-tunnel running and enrolled on the server
#   - Ziti Desktop Edge (ZDE) running locally for connection
#
# Usage:
#   ./scripts/add-https-to-server.sh              # Interactive mode
#   ./scripts/add-https-to-server.sh -y           # Non-interactive (use cached)
#   ./scripts/add-https-to-server.sh --non-interactive
# =============================================================================

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common functions
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
TF_IAM_DIR="$REPO_ROOT/infra/phase3-iam"
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"
CACHE_FILE="$REPO_ROOT/.add-https-cache"

# =============================================================================
# Parse Arguments
# =============================================================================

NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
if [[ "$1" == "--non-interactive" ]] || [[ "$1" == "-y" ]]; then
    NON_INTERACTIVE=true
fi

# =============================================================================
# Main Script
# =============================================================================

print_banner "TheraPrac - Add HTTPS to Server"
echo ""

# Ensure AWS credentials are valid
if ! ensure_aws_credentials; then
    exit 1
fi

echo ""
print_header "Server Configuration"

# Try to load cached values
if load_cache "$CACHE_FILE" && [ -n "$CACHED_TARGET_ENV" ]; then
    echo -e "${GREEN}Found cached values from last run:${NC}"
    echo "  Environment:    $CACHED_TARGET_ENV"
    echo "  Server Name:    $CACHED_SERVER_NAME"
    echo "  Ziti Controller: $CACHED_ZITI_CONTROLLER"
    echo "  Mock Backends:  $CACHED_DEPLOY_MOCKS"
    echo ""
    
    if [ "$NON_INTERACTIVE" = "true" ]; then
        REPLY="Y"
        echo -e "${BLUE}Use cached values? [Y/n]: Y (non-interactive)${NC}"
    else
        read -p "Use cached values? [Y/n] " -n 1 -r
        echo
    fi
    
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        TARGET_ENV="$CACHED_TARGET_ENV"
        SERVER_NAME="$CACHED_SERVER_NAME"
        ZITI_CONTROLLER="$CACHED_ZITI_CONTROLLER"
        DEPLOY_MOCKS="$CACHED_DEPLOY_MOCKS"
        echo -e "${GREEN}Using cached values${NC}"
    else
        # Clear cache and prompt for new values
        rm -f "$CACHE_FILE"
        CACHED_TARGET_ENV=""
    fi
fi

# Prompt for values if not loaded from cache
if [ -z "$TARGET_ENV" ]; then
    prompt_choice TARGET_ENV "Target environment" "dev, test, prod" "dev"
    prompt SERVER_NAME "Server name (e.g., app.mt or app.mt.dev)" ""
    prompt ZITI_CONTROLLER "Ziti controller URL" "https://ziti-nonprod.theraprac.com"
    prompt_choice DEPLOY_MOCKS "Deploy mock backends for testing?" "true, false" "false"
fi

# Derive values
# Handle both formats: "app.mt" or "app.mt.dev"
# If SERVER_NAME already ends with .${TARGET_ENV}, use it as-is
# Otherwise, append .${TARGET_ENV}
if [[ "$SERVER_NAME" == *.${TARGET_ENV} ]]; then
    # Server name already includes environment (e.g., app.mt.dev)
    FULL_SERVER_NAME="$SERVER_NAME"
    # Extract name.role part for Ansible host (e.g., app.mt.dev -> app.mt)
    SERVER_NAME_BASE="${SERVER_NAME%.${TARGET_ENV}}"
else
    # Server name is just name.role (e.g., app.mt), append environment
    FULL_SERVER_NAME="${SERVER_NAME}.${TARGET_ENV}"
    SERVER_NAME_BASE="$SERVER_NAME"
fi

SERVER_HOST="ssh.${FULL_SERVER_NAME}.ziti"
# Ziti identity matches the full server name (same as provision script)
ZITI_IDENTITY="${FULL_SERVER_NAME}"
# Convert dots to dashes for Ansible inventory host name: app.mt -> app-mt
SERVER_NAME_DASHED="${SERVER_NAME_BASE//./-}"
ANSIBLE_HOST="${SERVER_NAME_DASHED}-${TARGET_ENV}"

# Domain names
APP_DOMAIN="app-${TARGET_ENV}.theraprac.com"
API_DOMAIN="api-${TARGET_ENV}.theraprac.com"

echo ""
print_header "Configuration Summary"
echo -e "  Environment:     ${GREEN}${TARGET_ENV}${NC}"
echo -e "  Server Name:     ${SERVER_NAME}"
echo -e "  Server Host:     ${GREEN}${SERVER_HOST}${NC}"
echo -e "  Ziti Identity:   ${ZITI_IDENTITY}"
echo -e "  Ziti Controller: ${ZITI_CONTROLLER}"
echo -e "  Mock Backends:   ${DEPLOY_MOCKS}"
echo ""
echo -e "  App Domain:      ${GREEN}${APP_DOMAIN}${NC}"
echo -e "  API Domain:      ${GREEN}${API_DOMAIN}${NC}"
echo ""

if ! confirm "Continue with this configuration?"; then
    echo "Aborted."
    exit 0
fi

# Save to cache
save_cache "$CACHE_FILE" TARGET_ENV SERVER_NAME ZITI_CONTROLLER DEPLOY_MOCKS

# =============================================================================
# Step 1: Check Terraform IAM
# =============================================================================

print_header "Step 1: Checking Terraform IAM (Route53 permissions)"

cd "$TF_IAM_DIR"

# Refresh credentials before Terraform
refresh_aws_credentials || true

# Initialize Terraform
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init -reconfigure
fi

# Check for changes
echo -e "${YELLOW}Checking for pending Terraform changes...${NC}"
set +e
TF_PLAN_OUTPUT=$(terraform plan -detailed-exitcode 2>&1)
TF_EXIT_CODE=$?
set -e

case $TF_EXIT_CODE in
    0)
        echo -e "${GREEN}✓ Terraform IAM is up to date${NC}"
        ;;
    2)
        echo -e "${YELLOW}Terraform IAM has pending changes${NC}"
        echo ""
        echo "$TF_PLAN_OUTPUT"
        echo ""
        if confirm "Apply these Terraform changes?"; then
            echo -e "${YELLOW}Applying Terraform changes...${NC}"
            terraform apply -auto-approve
            echo -e "${GREEN}✓ Terraform apply complete${NC}"
        else
            echo -e "${YELLOW}Skipping Terraform apply. Continuing...${NC}"
        fi
        ;;
    1)
        # Exit code 1 means error - check if it's a credential issue
        if echo "$TF_PLAN_OUTPUT" | grep -q "AccessDenied\|no valid credential\|SSO session"; then
            echo -e "${YELLOW}Warning: Terraform credential issue detected${NC}"
            echo -e "${YELLOW}IAM policies may already exist. Continuing with Ansible deployment...${NC}"
            echo -e "${YELLOW}If deployment fails due to missing IAM policies, run terraform manually.${NC}"
        else
            echo -e "${YELLOW}Warning: Terraform check failed (see errors below)${NC}"
            echo "$TF_PLAN_OUTPUT" | tail -20
            echo ""
            echo -e "${YELLOW}Continuing with Ansible deployment...${NC}"
            echo -e "${YELLOW}If deployment fails, check Terraform state manually.${NC}"
        fi
        ;;
    *)
        echo -e "${YELLOW}Warning: Unexpected Terraform exit code ($TF_EXIT_CODE)${NC}"
        echo -e "${YELLOW}Continuing with Ansible deployment...${NC}"
        ;;
esac

cd "$REPO_ROOT"

# =============================================================================
# Step 2: Run Ansible Playbook
# =============================================================================

print_header "Step 2: Running Ansible Playbook"

cd "$ANSIBLE_DIR"

# Remove old host key from known_hosts (server may have been recreated)
echo -e "${YELLOW}Cleaning up old SSH host keys for ${SERVER_HOST}...${NC}"
ssh-keygen -R "${SERVER_HOST}" 2>/dev/null || true
ssh-keygen -R "${ANSIBLE_HOST}" 2>/dev/null || true
echo -e "${GREEN}✓ Host keys cleaned up${NC}"

# Check Ziti connectivity (warning only, not fatal)
echo -e "${YELLOW}Checking Ziti connectivity to ${SERVER_HOST}...${NC}"
if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes "ansible@${SERVER_HOST}" exit 0 2>/dev/null; then
    echo -e "${GREEN}✓ Ziti connection available${NC}"
else
    echo -e "${YELLOW}Warning: Cannot connect to server via Ziti${NC}"
    echo ""
    echo "This may be because:"
    echo "  1. Ziti Desktop Edge (ZDE) is not running locally"
    echo "  2. Your identity doesn't have access to: ${SERVER_HOST}"
    echo "  3. The server's ziti-edge-tunnel is not running"
    echo ""
    echo -e "${YELLOW}Attempting Ansible deployment anyway...${NC}"
    echo -e "${YELLOW}If it fails, ensure ZDE is running or use EICE for break-glass access.${NC}"
    echo ""
fi

echo ""
echo -e "${YELLOW}Running add-https.yml playbook...${NC}"
echo ""

# Create a temporary inventory file with the server host (YAML format)
# Use portable mktemp syntax (BSD/macOS compatible)
TEMP_INVENTORY="/tmp/ansible-inventory-$$.yml"
cat > "$TEMP_INVENTORY" <<EOF
all:
  hosts:
    ${ANSIBLE_HOST}:
      ansible_host: ${SERVER_HOST}
      ansible_port: 22
      ansible_user: ansible
      ansible_connection: ssh
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519_ansible_1
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF

# Try Ziti inventory first, fall back to EICE if Ziti routing is wrong
# Use pipefail to capture ansible exit code through the tee pipe
set -o pipefail
if ansible-playbook -i "$TEMP_INVENTORY" add-https.yml \
    --limit "${ANSIBLE_HOST}" \
    -e "target_env=${TARGET_ENV}" \
    -e "ziti_identity_name=${ZITI_IDENTITY}" \
    -e "ziti_controller_endpoint=${ZITI_CONTROLLER}" \
    -e "deploy_mock_backends=${DEPLOY_MOCKS}" 2>&1 | tee /tmp/ansible-ziti.log; then
    # Check if hosts actually ran (not just skipped)
    if grep -q "skipping: no hosts matched" /tmp/ansible-ziti.log || \
       grep -q "No inventory was parsed" /tmp/ansible-ziti.log || \
       grep -q "provided hosts list is empty" /tmp/ansible-ziti.log; then
        echo -e "${RED}✗ No hosts matched or inventory parsing failed${NC}"
        rm -f "$TEMP_INVENTORY"
        echo -e "${YELLOW}Trying EICE fallback...${NC}"
        echo ""
        # Use EICE inventory as fallback
        if ! ansible-playbook -i inventory/server-eice.yml add-https.yml \
            -e "target_env=${TARGET_ENV}" \
            -e "ziti_identity_name=${ZITI_IDENTITY}" \
            -e "ziti_controller_endpoint=${ZITI_CONTROLLER}" \
            -e "deploy_mock_backends=${DEPLOY_MOCKS}"; then
            echo -e "${RED}✗ EICE fallback also failed${NC}"
            exit 1
        fi
    elif ! grep -q "changed=\|ok=" /tmp/ansible-ziti.log; then
        # No tasks actually ran
        echo -e "${RED}✗ No tasks were executed${NC}"
        rm -f "$TEMP_INVENTORY"
        echo -e "${YELLOW}Trying EICE fallback...${NC}"
        echo ""
        # Use EICE inventory as fallback
        if ! ansible-playbook -i inventory/server-eice.yml add-https.yml \
            -e "target_env=${TARGET_ENV}" \
            -e "ziti_identity_name=${ZITI_IDENTITY}" \
            -e "ziti_controller_endpoint=${ZITI_CONTROLLER}" \
            -e "deploy_mock_backends=${DEPLOY_MOCKS}"; then
            echo -e "${RED}✗ EICE fallback also failed${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Deployment via Ziti successful${NC}"
        rm -f "$TEMP_INVENTORY"
    fi
else
    ANSIBLE_EXIT=$?
    rm -f "$TEMP_INVENTORY"
    # Check if it was a connection failure vs playbook failure
    if grep -q "UNREACHABLE\|Connection refused\|No route to host\|Could not match supplied host pattern\|skipping: no hosts matched" /tmp/ansible-ziti.log; then
        echo -e "${YELLOW}Ziti connection failed, trying EICE fallback...${NC}"
        echo ""
        # Use EICE inventory as fallback
        if ! ansible-playbook -i inventory/server-eice.yml add-https.yml \
            -e "target_env=${TARGET_ENV}" \
            -e "ziti_identity_name=${ZITI_IDENTITY}" \
            -e "ziti_controller_endpoint=${ZITI_CONTROLLER}" \
            -e "deploy_mock_backends=${DEPLOY_MOCKS}"; then
            echo -e "${RED}✗ EICE fallback also failed${NC}"
            exit 1
        fi
    else
        echo -e "${RED}✗ Ansible playbook failed (exit code: ${ANSIBLE_EXIT})${NC}"
        echo -e "${RED}  Check /tmp/ansible-ziti.log for details${NC}"
        exit 1
    fi
fi
set +o pipefail

cd "$REPO_ROOT"

# =============================================================================
# Done
# =============================================================================

echo ""
print_success_banner "HTTPS Setup Complete!"
echo ""
echo -e "  Environment: ${TARGET_ENV}"
echo -e "  Server:      ${SERVER_HOST}"
echo ""
echo -e "  ${BLUE}Services available via Ziti:${NC}"
echo -e "    Web App: https://${APP_DOMAIN}"
echo -e "    API:     https://${API_DOMAIN}"
echo ""
echo -e "  ${BLUE}Verify certificates:${NC}"
echo -e "    ssh ansible@${SERVER_HOST} 'sudo certbot certificates'"
echo ""
echo -e "  ${BLUE}Check nginx status:${NC}"
echo -e "    ssh ansible@${SERVER_HOST} 'systemctl status nginx'"
echo ""
if [ "$DEPLOY_MOCKS" = "true" ]; then
    echo -e "  ${YELLOW}Mock backends deployed for testing${NC}"
    echo -e "    Stop when ready: ssh ansible@${SERVER_HOST} 'sudo systemctl stop mock-app mock-api'"
    echo ""
fi

