#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Deploy Web
# =============================================================================
# Deploys the TheraPrac Web application to a server.
#
# This script:
#   1. Validates AWS credentials
#   2. Validates build exists in S3
#   3. Runs Ansible deploy-web.yml playbook
#   4. Verifies deployment health
#
# Prerequisites:
#   - Server already provisioned via provision-basic-server.sh
#   - HTTPS configured via add-https-to-server.sh
#   - Web build uploaded to S3
#
# Usage:
#   ./scripts/deploy-web.sh                    # Interactive mode
#   ./scripts/deploy-web.sh -y                 # Non-interactive (use cached)
#   ./scripts/deploy-web.sh --non-interactive
#
# Version formats:
#   - latest                → builds/{env}/main/latest/
#   - main/latest           → builds/{env}/main/latest/
#   - feature-xyz/latest    → builds/{env}/feature-xyz/latest/
#   - main/v0.1.0-dev.1     → builds/{env}/main/v0.1.0-dev.1/
#   - v0.1.0                → releases/v0.1.0/ (final release)
# =============================================================================

set -e

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common functions
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"
CACHE_FILE="$REPO_ROOT/.deploy-web-cache"
S3_BUCKET="${S3_BUCKET:-theraprac-web}"

# =============================================================================
# Parse Arguments
# =============================================================================

NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--non-interactive|-y]"
            exit 1
            ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

# Parse version string and determine S3 path
# Outputs: S3_PATH, IS_RELEASE
parse_version() {
    local env="$1"
    local version="$2"
    
    # Final release: v{version} → releases/{version}/
    if [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        S3_PATH="releases/${version}"
        IS_RELEASE=true
        return 0
    fi
    
    # Just "latest" → main/latest
    if [ "$version" = "latest" ]; then
        S3_PATH="builds/${env}/main/latest"
        IS_RELEASE=false
        return 0
    fi
    
    # {branch}/latest or {branch}/{tag}
    if [[ "$version" == *"/"* ]]; then
        local branch="${version%%/*}"
        local tag="${version#*/}"
        S3_PATH="builds/${env}/${branch}/${tag}"
        IS_RELEASE=false
        return 0
    fi
    
    # Single tag without branch → builds/{env}/main/{version}
    S3_PATH="builds/${env}/main/${version}"
    IS_RELEASE=false
}

# Validate build exists in S3
validate_build() {
    local s3_path="$1"
    local temp_file=$(mktemp)
    
    echo -e "${YELLOW}Validating build at s3://${S3_BUCKET}/${s3_path}/...${NC}"
    
    # Download manifest
    if ! aws s3 cp "s3://${S3_BUCKET}/${s3_path}/manifest.json" "$temp_file" >/dev/null 2>&1; then
        echo -e "${RED}Error: Manifest not found at s3://${S3_BUCKET}/${s3_path}/manifest.json${NC}"
        rm -f "$temp_file"
        return 1
    fi
    
    # Validate manifest
    if ! jq -e '.version and .environment and .branch and .build_timestamp' "$temp_file" >/dev/null 2>&1; then
        echo -e "${RED}Error: Manifest is incomplete${NC}"
        rm -f "$temp_file"
        return 1
    fi
    
    # Extract details
    MANIFEST_VERSION=$(jq -r '.version' "$temp_file")
    MANIFEST_ENV=$(jq -r '.environment' "$temp_file")
    MANIFEST_BRANCH=$(jq -r '.branch' "$temp_file")
    MANIFEST_TAG=$(jq -r '.tag' "$temp_file")
    MANIFEST_COMMIT=$(jq -r '.commit_short' "$temp_file")
    MANIFEST_TIMESTAMP=$(jq -r '.build_timestamp' "$temp_file")
    
    # Check tarball exists
    local tarball="theraprac-web-${MANIFEST_VERSION}-${MANIFEST_ENV}.tar.gz"
    if ! aws s3 ls "s3://${S3_BUCKET}/${s3_path}/${tarball}" >/dev/null 2>&1; then
        echo -e "${RED}Error: Tarball not found: ${tarball}${NC}"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    
    echo -e "${GREEN}✓ Build validated${NC}"
    echo -e "  Tag:       ${MANIFEST_TAG}"
    echo -e "  Version:   ${MANIFEST_VERSION}"
    echo -e "  Branch:    ${MANIFEST_BRANCH}"
    echo -e "  Commit:    ${MANIFEST_COMMIT}"
    echo -e "  Built:     ${MANIFEST_TIMESTAMP}"
    
    return 0
}

# =============================================================================
# Main Script
# =============================================================================

print_banner "TheraPrac - Deploy Web"
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
        VERSION="$CACHED_VERSION"
        SERVER_NAME="$CACHED_SERVER_NAME"
        TARGET_ENV="$CACHED_TARGET_ENV"
    else
        echo -e "${GREEN}Found cached values from last run:${NC}"
        echo "  Environment:  $CACHED_TARGET_ENV"
        echo "  Version:      $CACHED_VERSION"
        echo "  Server Name:  $CACHED_SERVER_NAME"
        echo ""
        read -p "Use cached values? [Y/n] " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            VERSION="$CACHED_VERSION"
            SERVER_NAME="$CACHED_SERVER_NAME"
            TARGET_ENV="$CACHED_TARGET_ENV"
            echo -e "${GREEN}Using cached values${NC}"
        else
            rm -f "$CACHE_FILE"
            CACHED_SERVER_NAME=""
        fi
    fi
fi

# Prompt for values if not loaded from cache
if [ -z "$SERVER_NAME" ]; then
    prompt TARGET_ENV "Target environment (dev, test, prod)" "dev"
    prompt VERSION "Build version (latest, main/latest, branch/tag, or v0.1.0 for release)" "latest"
    prompt SERVER_NAME "Server name (e.g., web.mt.dev, theraprac.mt.prod)" ""
fi

# Validate environment
if [[ ! "$TARGET_ENV" =~ ^(dev|test|prod)$ ]]; then
    echo -e "${RED}Error: Invalid environment '${TARGET_ENV}'${NC}"
    echo "Valid environments: dev, test, prod"
    exit 1
fi

# Parse version and get S3 path
parse_version "$TARGET_ENV" "$VERSION"

# Derive values
SERVER_HOST="ssh.${SERVER_NAME}.ziti"
SERVER_NAME_DASHED="${SERVER_NAME//./-}"
ANSIBLE_HOST="${SERVER_NAME_DASHED}"
WEB_DOMAIN="${TARGET_ENV}.theraprac.com"

echo ""
print_header "Configuration Summary"
echo -e "  Environment:   ${GREEN}${TARGET_ENV}${NC}"
echo -e "  Version:       ${GREEN}${VERSION}${NC}"
echo -e "  Server Name:   ${SERVER_NAME}"
echo -e "  Server Host:   ${GREEN}${SERVER_HOST}${NC}"
echo -e "  S3 Path:       ${S3_PATH}"
echo -e "  Release:       ${IS_RELEASE}"
echo ""

# Validate the build exists
if ! validate_build "$S3_PATH"; then
    echo ""
    echo -e "${RED}Build validation failed${NC}"
    echo ""
    echo "Available builds:"
    echo "  ./scripts/list-web-builds.sh"
    exit 1
fi

echo ""
if ! confirm "Continue with this deployment?"; then
    echo "Aborted."
    exit 0
fi

# Save to cache
save_cache "$CACHE_FILE" VERSION SERVER_NAME TARGET_ENV

# =============================================================================
# Step 1: Run Ansible Playbook
# =============================================================================

print_header "Step 1: Running Ansible Playbook"

cd "$ANSIBLE_DIR"

# Check if the playbook and role exist
if [ ! -f "deploy-web.yml" ]; then
    echo -e "${RED}Error: deploy-web.yml playbook not found${NC}"
    echo "Please create the playbook and theraprac-web role first."
    exit 1
fi

# Remove old host key from known_hosts
echo -e "${YELLOW}Cleaning up old SSH host keys for ${SERVER_HOST}...${NC}"
ssh-keygen -R "${SERVER_HOST}" 2>/dev/null || true
ssh-keygen -R "${ANSIBLE_HOST}" 2>/dev/null || true
echo -e "${GREEN}✓ Host keys cleaned up${NC}"

# Check Ziti connectivity
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
    echo ""
fi

echo ""
echo -e "${YELLOW}Running deploy-web.yml playbook...${NC}"
echo ""

ansible-playbook -i inventory/ziti.yml deploy-web.yml \
    --limit "${ANSIBLE_HOST}" \
    -e "target_env=${TARGET_ENV}" \
    -e "version=${VERSION}" \
    -e "s3_path=${S3_PATH}" \
    -e "s3_bucket=${S3_BUCKET}" \
    -e "aws_account_id=${AWS_ACCOUNT_ID}"

cd "$REPO_ROOT"

# =============================================================================
# Step 2: Health Check
# =============================================================================

print_header "Step 2: Verifying Deployment"

echo -e "${YELLOW}Waiting for web application to be healthy...${NC}"

# Give the service a moment to start
sleep 5

# Try health check via Ziti
HEALTH_OK=false
for i in {1..30}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "ansible@${SERVER_HOST}" \
        "curl -sf http://localhost:3000/" >/dev/null 2>&1; then
        HEALTH_OK=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$HEALTH_OK" = "true" ]; then
    echo -e "${GREEN}✓ Web health check passed${NC}"
else
    echo -e "${YELLOW}Warning: Health check did not complete${NC}"
    echo "Check logs: ssh ansible@${SERVER_HOST} 'journalctl -u theraprac-web -n 50'"
fi

# =============================================================================
# Done
# =============================================================================

echo ""
print_success_banner "Web Deployment Complete!"
echo ""
echo -e "  Environment: ${TARGET_ENV}"
echo -e "  Version:     ${VERSION}"
echo -e "  Branch:      ${MANIFEST_BRANCH}"
echo -e "  Commit:      ${MANIFEST_COMMIT}"
echo -e "  Server:      ${SERVER_HOST}"
echo ""
echo -e "  ${BLUE}Web available at:${NC}"
echo -e "    https://${WEB_DOMAIN}"
echo ""
echo -e "  ${BLUE}View logs:${NC}"
echo -e "    ssh ansible@${SERVER_HOST} 'journalctl -u theraprac-web -f'"
echo ""
echo -e "  ${BLUE}Service status:${NC}"
echo -e "    ssh ansible@${SERVER_HOST} 'systemctl status theraprac-web'"
echo ""

