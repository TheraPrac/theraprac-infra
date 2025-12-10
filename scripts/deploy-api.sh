#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Deploy API
# =============================================================================
# Deploys the TheraPrac API to a server with AWS configuration.
#
# This script:
#   1. Validates AWS credentials
#   2. Checks/applies Terraform IAM (KMS + SSM permissions)
#   3. Validates AWS resources exist (KMS, Secrets Manager, SSM)
#   4. Runs Ansible deploy-api.yml playbook
#   5. Verifies deployment health
#
# Prerequisites:
#   - Server already provisioned via provision-basic-server.sh
#   - HTTPS configured via add-https-to-server.sh
#   - AWS resources created via setup-aws-config.sh (or run with --bootstrap)
#   - API binary built and uploaded to S3
#
# Usage:
#   ./scripts/deploy-api.sh                    # Interactive mode
#   ./scripts/deploy-api.sh -y                 # Non-interactive (use cached)
#   ./scripts/deploy-api.sh --non-interactive
#   ./scripts/deploy-api.sh --bootstrap        # Create missing AWS resources
# =============================================================================

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
API_REPO_ROOT="$(cd "$REPO_ROOT/../theraprac-api" && pwd)"

# Source common functions
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
TF_IAM_DIR="$REPO_ROOT/infra/phase3-iam"
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"
CACHE_FILE="$REPO_ROOT/.deploy-api-cache"
SETUP_SCRIPT="$API_REPO_ROOT/scripts/setup-aws-config.sh"

# =============================================================================
# Parse Arguments
# =============================================================================

NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
BOOTSTRAP_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --bootstrap)
            BOOTSTRAP_MODE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--non-interactive|-y] [--bootstrap]"
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Script
# =============================================================================

print_banner "TheraPrac - Deploy API"
echo ""

# Ensure AWS credentials are valid
if ! ensure_aws_credentials; then
    exit 1
fi

# Get AWS account ID
AWS_ACCOUNT_ID=$(get_aws_account_id)
echo -e "AWS Account: ${GREEN}${AWS_ACCOUNT_ID}${NC}"

echo ""
print_header "Deployment Configuration"

# Try to load cached values
if load_cache "$CACHE_FILE" && [ -n "$CACHED_SERVER_NAME" ]; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
        # Non-interactive mode: use cached values directly, no prompt
        VERSION="$CACHED_VERSION"
        SERVER_NAME="$CACHED_SERVER_NAME"
        S3_BUCKET="$CACHED_S3_BUCKET"
    else
        # Interactive mode: show cached values and prompt
        echo -e "${GREEN}Found cached values from last run:${NC}"
        echo "  Version:      $CACHED_VERSION"
        echo "  Server Name:  $CACHED_SERVER_NAME"
        echo "  S3 Bucket:    $CACHED_S3_BUCKET"
        echo ""
        read -p "Use cached values? [Y/n] " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            VERSION="$CACHED_VERSION"
            SERVER_NAME="$CACHED_SERVER_NAME"
            S3_BUCKET="$CACHED_S3_BUCKET"
            echo -e "${GREEN}Using cached values${NC}"
        else
            # Clear cache and prompt for new values
            rm -f "$CACHE_FILE"
            CACHED_SERVER_NAME=""
        fi
    fi
fi

# Prompt for values if not loaded from cache
if [ -z "$SERVER_NAME" ]; then
    prompt VERSION "API version to deploy (latest, 0.1.0, or branch/commit like fix/remaining-lint-errors/74dc437)" "latest"
    prompt SERVER_NAME "Server name (e.g., app.mt.dev, theraprac.mt.prod)" ""
    prompt S3_BUCKET "S3 artifact bucket" "theraprac-artifacts"
fi

# Extract environment from the last segment of server name
# e.g., app.mt.dev -> dev, theraprac.mt.prod -> prod
TARGET_ENV="${SERVER_NAME##*.}"

# Validate extracted environment
if [[ ! "$TARGET_ENV" =~ ^(dev|test|prod|nonprod)$ ]]; then
    echo -e "${RED}Error: Invalid environment '${TARGET_ENV}' in server name${NC}"
    echo "Server name must end with: dev, test, prod, or nonprod"
    echo "Example: app.mt.dev, theraprac.mt.prod"
    exit 1
fi

# Derive values - server name already includes environment
SERVER_HOST="ssh.${SERVER_NAME}.ziti"
# Convert dots to dashes for Ansible inventory host name: app.mt.dev -> app-mt-dev
SERVER_NAME_DASHED="${SERVER_NAME//./-}"
ANSIBLE_HOST="${SERVER_NAME_DASHED}"
API_DOMAIN="api-${TARGET_ENV}.theraprac.com"

echo ""
print_header "Configuration Summary"
echo -e "  Server Name:   ${SERVER_NAME}"
echo -e "  Environment:   ${GREEN}${TARGET_ENV}${NC} (extracted from server name)"
echo -e "  Version:       ${GREEN}${VERSION}${NC}"
echo -e "  Server Host:   ${GREEN}${SERVER_HOST}${NC}"
echo -e "  S3 Bucket:     ${S3_BUCKET}"
echo -e "  AWS Account:   ${AWS_ACCOUNT_ID}"
echo ""
echo -e "  API Domain:    ${GREEN}${API_DOMAIN}${NC}"
echo ""

if ! confirm "Continue with this configuration?"; then
    echo "Aborted."
    exit 0
fi

# Save to cache
save_cache "$CACHE_FILE" VERSION SERVER_NAME S3_BUCKET

# =============================================================================
# Step 1: Check Terraform IAM
# =============================================================================

print_header "Step 1: Checking Terraform IAM (KMS + SSM permissions)"

cd "$TF_IAM_DIR"

# Refresh credentials before Terraform (explicitly use admin profile for IAM access)
eval $(aws configure export-credentials --profile "${AWS_PROFILE:-jfinlinson_admin}" --format env 2>/dev/null) || {
    echo -e "${RED}Failed to export AWS credentials${NC}"
    exit 1
}

# Initialize Terraform (always reconfigure to pick up fresh credentials)
echo -e "${YELLOW}Initializing Terraform...${NC}"
if ! terraform init -reconfigure >/dev/null 2>&1; then
    echo -e "${RED}Terraform init failed. Retrying with verbose output...${NC}"
    terraform init -reconfigure
    exit 1
fi

# Check for changes (use admin profile for IAM access)
TF_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"
TF_PLAN_FILE="/tmp/deploy-api-iam.tfplan"
echo -e "${YELLOW}Checking for pending Terraform changes...${NC}"
set +e
terraform plan -detailed-exitcode -var="aws_profile=${TF_PROFILE}" -out="$TF_PLAN_FILE" >/dev/null 2>&1
TF_EXIT_CODE=$?
set -e

case $TF_EXIT_CODE in
    0)
        echo -e "${GREEN}✓ Terraform IAM is up to date${NC}"
        rm -f "$TF_PLAN_FILE"
        ;;
    2)
        echo -e "${YELLOW}Terraform IAM has pending changes${NC}"
        echo ""
        terraform show "$TF_PLAN_FILE"
        echo ""
        if confirm "Apply these Terraform changes?"; then
            echo -e "${YELLOW}Applying Terraform changes...${NC}"
            terraform apply "$TF_PLAN_FILE"
            echo -e "${GREEN}✓ Terraform apply complete${NC}"
        else
            echo -e "${YELLOW}Skipping Terraform apply. Continuing...${NC}"
        fi
        rm -f "$TF_PLAN_FILE"
        ;;
    *)
        echo -e "${RED}Error checking Terraform state (exit code: $TF_EXIT_CODE)${NC}"
        terraform plan -var="aws_profile=${TF_PROFILE}"
        echo ""
        echo "You may need to run: cd $TF_IAM_DIR && terraform init"
        rm -f "$TF_PLAN_FILE"
        exit 1
        ;;
esac

cd "$REPO_ROOT"

# =============================================================================
# Step 2: Validate AWS Resources
# =============================================================================

print_header "Step 2: Validating AWS Resources"

# Check if setup script exists
if [ ! -f "$SETUP_SCRIPT" ]; then
    echo -e "${RED}Error: Setup script not found: $SETUP_SCRIPT${NC}"
    echo "Please ensure theraprac-api repository is at: $API_REPO_ROOT"
    exit 1
fi

# Run validation
echo -e "${YELLOW}Checking AWS resources for environment: ${TARGET_ENV}${NC}"
echo ""

set +e
"$SETUP_SCRIPT" --environment "$TARGET_ENV" --validate-only
VALIDATE_EXIT=$?
set -e

if [ $VALIDATE_EXIT -eq 0 ]; then
    echo -e "${GREEN}✓ All AWS resources exist${NC}"
else
    echo ""
    echo -e "${YELLOW}Some AWS resources are missing${NC}"
    
    if [ "$BOOTSTRAP_MODE" = "true" ]; then
        echo -e "${BLUE}Bootstrap mode: Creating missing resources...${NC}"
        if [ "$NON_INTERACTIVE" = "true" ]; then
            "$SETUP_SCRIPT" --environment "$TARGET_ENV" --non-interactive
        else
            "$SETUP_SCRIPT" --environment "$TARGET_ENV"
        fi
    else
        echo ""
        echo "Options:"
        echo "  1. Run this script with --bootstrap to create resources"
        echo "  2. Run setup manually: $SETUP_SCRIPT --environment $TARGET_ENV"
        echo ""
        
        if confirm "Create missing AWS resources now?"; then
            if [ "$NON_INTERACTIVE" = "true" ]; then
                "$SETUP_SCRIPT" --environment "$TARGET_ENV" --non-interactive
            else
                "$SETUP_SCRIPT" --environment "$TARGET_ENV"
            fi
        else
            echo -e "${RED}Cannot proceed without required AWS resources${NC}"
            exit 1
        fi
    fi
fi

# =============================================================================
# Step 2.5: Update Database Host Parameter
# =============================================================================

print_header "Step 2.5: Updating Database Host Parameter"

SSM_DB_HOST="/theraprac/api/${TARGET_ENV}/db-host"
ZITI_DB_HOST="postgres.db.${TARGET_ENV}.app.ziti"

echo -e "${YELLOW}Setting ${SSM_DB_HOST} = ${ZITI_DB_HOST}${NC}"

if aws ssm put-parameter \
    --name "$SSM_DB_HOST" \
    --value "$ZITI_DB_HOST" \
    --type "String" \
    --overwrite \
    --region "${AWS_REGION:-us-west-2}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Database host parameter updated${NC}"
else
    echo -e "${RED}Failed to update database host parameter${NC}"
    echo "You may need to create it manually:"
    echo "  aws ssm put-parameter --name '$SSM_DB_HOST' --value '$ZITI_DB_HOST' --type String"
    exit 1
fi

# =============================================================================
# Step 3: Run Ansible Playbook
# =============================================================================

print_header "Step 3: Running Ansible Playbook"

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
echo -e "${YELLOW}Running deploy-api.yml playbook...${NC}"
echo ""

ansible-playbook -i inventory/ziti.yml deploy-api.yml \
    --limit "${ANSIBLE_HOST}" \
    -e "target_env=${TARGET_ENV}" \
    -e "version=${VERSION}" \
    -e "s3_bucket=${S3_BUCKET}" \
    -e "aws_account_id=${AWS_ACCOUNT_ID}"

cd "$REPO_ROOT"

# =============================================================================
# Step 4: Health Check
# =============================================================================

print_header "Step 4: Verifying Deployment"

echo -e "${YELLOW}Checking service status...${NC}"

# Auto-detect which SSH user works
SSH_USER="ansible"
if ! ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes "ansible@${SERVER_HOST}" "echo test" >/dev/null 2>&1; then
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes "jfinlinson@${SERVER_HOST}" "echo test" >/dev/null 2>&1; then
        SSH_USER="jfinlinson"
        echo -e "${YELLOW}Note: Using jfinlinson user (ansible not available)${NC}"
    fi
fi

# Give the service a moment to start
sleep 5

# First, check if the service is running
SERVICE_ACTIVE=false
for i in {1..10}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "systemctl is-active --quiet theraprac-api" 2>/dev/null; then
        SERVICE_ACTIVE=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$SERVICE_ACTIVE" != "true" ]; then
    echo -e "${RED}✗ Service is not active${NC}"
    echo "Checking service status..."
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "systemctl status theraprac-api --no-pager -n 20" 2>&1 || true
    echo ""
    echo "Check logs: ssh ${SSH_USER}@${SERVER_HOST} 'journalctl -u theraprac-api -n 50'"
    exit 1
fi

echo -e "${GREEN}✓ Service is active${NC}"
echo -e "${YELLOW}Waiting for API to be healthy...${NC}"

# Try health check via Ziti (if available)
# Note: The API endpoint is /health (not /healthz)
HEALTH_OK=false
HEALTH_RESPONSE=""
for i in {1..30}; do
    HEALTH_RESPONSE=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "curl -sf http://localhost:8080/health" 2>&1)
    if [ $? -eq 0 ] && [ -n "$HEALTH_RESPONSE" ]; then
        HEALTH_OK=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$HEALTH_OK" = "true" ]; then
    echo -e "${GREEN}✓ API health check passed${NC}"
    # Show a summary of the health response
    echo "$HEALTH_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 || true
else
    echo -e "${YELLOW}Warning: Health check did not complete${NC}"
    if [ -n "$HEALTH_RESPONSE" ]; then
        echo "Health check response:"
        echo "$HEALTH_RESPONSE"
    fi
    echo ""
    echo "Check logs: ssh ${SSH_USER}@${SERVER_HOST} 'journalctl -u theraprac-api -n 50'"
    echo "Check service: ssh ${SSH_USER}@${SERVER_HOST} 'systemctl status theraprac-api'"
fi

# =============================================================================
# Done
# =============================================================================

echo ""
print_success_banner "API Deployment Complete!"
echo ""
echo -e "  Environment: ${TARGET_ENV}"
echo -e "  Version:     ${VERSION}"
echo -e "  Server:      ${SERVER_HOST}"
echo ""
echo -e "  ${BLUE}API available at:${NC}"
echo -e "    https://${API_DOMAIN}"
echo ""
  echo -e "  ${BLUE}Health check:${NC}"
  echo -e "    curl https://${API_DOMAIN}/health"
echo ""
echo -e "  ${BLUE}View logs:${NC}"
echo -e "    ssh ${SSH_USER:-ansible}@${SERVER_HOST} 'journalctl -u theraprac-api -f'"
echo ""
echo -e "  ${BLUE}Service status:${NC}"
echo -e "    ssh ${SSH_USER:-ansible}@${SERVER_HOST} 'systemctl status theraprac-api'"
echo ""

