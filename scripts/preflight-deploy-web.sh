#!/bin/bash
# =============================================================================
# Pre-flight Check for Web Deployment
# =============================================================================
# Validates all prerequisites before deploying the web application
#
# Usage:
#   ./scripts/preflight-deploy-web.sh <environment> <server-name> <version>
#   ./scripts/preflight-deploy-web.sh dev web.mt.dev latest
#   ./scripts/preflight-deploy-web.sh dev web.mt.dev main/v0.1.0-dev.1
#   ./scripts/preflight-deploy-web.sh prod web.mt.prod v0.1.0
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
CACHE_FILE="$REPO_ROOT/.deploy-web-cache"

# =============================================================================
# Parse Arguments
# =============================================================================

if [ $# -lt 3 ]; then
    echo "Usage: $0 <environment> <server-name> <version>"
    echo ""
    echo "Examples:"
    echo "  $0 dev web.mt.dev latest"
    echo "  $0 dev web.mt.dev main/latest"
    echo "  $0 dev web.mt.dev feature-xyz/v0.1.0-dev.1"
    echo "  $0 prod web.mt.prod v0.1.0"
    echo ""
    echo "Environment: dev, test, prod"
    echo "Server name: e.g., web.mt.dev, theraprac.mt.prod"
    echo "Version formats:"
    echo "  - latest                → builds/{env}/main/latest/"
    echo "  - main/latest           → builds/{env}/main/latest/"
    echo "  - branch/latest         → builds/{env}/{branch}/latest/"
    echo "  - branch/tag            → builds/{env}/{branch}/{tag}/"
    echo "  - v0.1.0                → releases/v0.1.0/ (final release)"
    exit 1
fi

TARGET_ENV="$1"
SERVER_NAME="$2"
VERSION="$3"

# Validate environment
if [[ ! "$TARGET_ENV" =~ ^(dev|test|prod)$ ]]; then
    echo -e "${RED}Error: Invalid environment '${TARGET_ENV}'${NC}"
    echo "Environment must be: dev, test, or prod"
    exit 1
fi

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"
S3_BUCKET="${S3_BUCKET:-theraprac-web}"
ANSIBLE_SSH_KEY="${ANSIBLE_SSH_KEY:-~/.ssh/id_ed25519_ansible_1}"

# Expand tilde in SSH key path
ANSIBLE_SSH_KEY="${ANSIBLE_SSH_KEY/#\~/$HOME}"

# =============================================================================
# Helper Functions
# =============================================================================

# Parse version string and determine S3 path
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

# =============================================================================
# Parse Version and Determine S3 Path
# =============================================================================

parse_version "$TARGET_ENV" "$VERSION"

# Derived values
SERVER_HOST="ssh.${SERVER_NAME}.ziti"
SERVER_NAME_DASHED="${SERVER_NAME//./-}"

# Save provided parameters to cache (for deploy script to use later)
cat > "$CACHE_FILE" <<EOF
CACHED_SERVER_NAME="$SERVER_NAME"
CACHED_VERSION="$VERSION"
CACHED_TARGET_ENV="$TARGET_ENV"
EOF

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pre-flight Check for Web Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Environment: ${GREEN}${TARGET_ENV}${NC}"
echo -e "Server:      ${GREEN}${SERVER_NAME}${NC}"
echo -e "Server Host: ${GREEN}${SERVER_HOST}${NC}"
echo -e "Version:     ${GREEN}${VERSION}${NC}"
echo -e "S3 Bucket:   ${GREEN}${S3_BUCKET}${NC}"
echo -e "S3 Path:     ${GREEN}${S3_PATH}${NC}"
echo -e "Is Release:  ${GREEN}${IS_RELEASE}${NC}"
echo ""

ERRORS=0
WARNINGS=0
ERROR_LIST=()
WARNING_LIST=()

# =============================================================================
# 1. Check AWS Credentials
# =============================================================================
echo -e "${YELLOW}[1/6] Checking AWS credentials...${NC}"
if aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
    echo -e "  ${GREEN}✓${NC} AWS credentials valid (Account: ${AWS_ACCOUNT_ID})"
else
    echo -e "  ${RED}✗${NC} AWS credentials invalid or expired"
    ERROR_LIST+=("AWS credentials are invalid or expired. Run: aws sso login --profile $AWS_PROFILE")
    ((ERRORS++))
fi

# =============================================================================
# 2. Check S3 Bucket Access
# =============================================================================
echo -e "${YELLOW}[2/6] Checking S3 bucket access...${NC}"
if aws s3 ls "s3://${S3_BUCKET}/" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} S3 bucket accessible: ${S3_BUCKET}"
else
    echo -e "  ${RED}✗${NC} Cannot access S3 bucket: ${S3_BUCKET}"
    ERROR_LIST+=("S3 bucket ${S3_BUCKET} is not accessible")
    ((ERRORS++))
fi

# =============================================================================
# 3. Check Build Exists in S3
# =============================================================================
echo -e "${YELLOW}[3/6] Checking build exists in S3...${NC}"

# Check manifest exists
MANIFEST_PATH="s3://${S3_BUCKET}/${S3_PATH}/manifest.json"
TEMP_MANIFEST=$(mktemp)
if aws s3 cp "$MANIFEST_PATH" "$TEMP_MANIFEST" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Manifest found"
    
    # Validate manifest contents
    if jq -e '.version and .environment and .branch and .build_timestamp' "$TEMP_MANIFEST" >/dev/null 2>&1; then
        MANIFEST_VERSION=$(jq -r '.version' "$TEMP_MANIFEST")
        MANIFEST_ENV=$(jq -r '.environment' "$TEMP_MANIFEST")
        MANIFEST_BRANCH=$(jq -r '.branch' "$TEMP_MANIFEST")
        MANIFEST_TAG=$(jq -r '.tag' "$TEMP_MANIFEST")
        MANIFEST_COMMIT=$(jq -r '.commit_short' "$TEMP_MANIFEST")
        MANIFEST_TIMESTAMP=$(jq -r '.build_timestamp' "$TEMP_MANIFEST")
        
        echo -e "  ${GREEN}✓${NC} Manifest valid"
        echo -e "      Tag:       ${MANIFEST_TAG}"
        echo -e "      Version:   ${MANIFEST_VERSION}"
        echo -e "      Branch:    ${MANIFEST_BRANCH}"
        echo -e "      Commit:    ${MANIFEST_COMMIT}"
        echo -e "      Built:     ${MANIFEST_TIMESTAMP}"
        
        # Check tarball exists
        TARBALL_NAME="theraprac-web-${MANIFEST_VERSION}-${MANIFEST_ENV}.tar.gz"
        TARBALL_PATH="s3://${S3_BUCKET}/${S3_PATH}/${TARBALL_NAME}"
        if aws s3 ls "$TARBALL_PATH" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Tarball found: ${TARBALL_NAME}"
            
            # Check checksum exists
            CHECKSUM_PATH="${TARBALL_PATH}.sha256"
            if aws s3 ls "$CHECKSUM_PATH" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} Checksum found"
            else
                echo -e "  ${YELLOW}!${NC} Checksum missing (deployment will continue without verification)"
                WARNING_LIST+=("Tarball checksum file not found")
                ((WARNINGS++))
            fi
        else
            echo -e "  ${RED}✗${NC} Tarball not found: ${TARBALL_NAME}"
            ERROR_LIST+=("Tarball not found at ${TARBALL_PATH}")
            ((ERRORS++))
        fi
    else
        echo -e "  ${RED}✗${NC} Manifest is incomplete or invalid"
        ERROR_LIST+=("Manifest at ${MANIFEST_PATH} is incomplete")
        ((ERRORS++))
    fi
else
    echo -e "  ${RED}✗${NC} Manifest not found: ${MANIFEST_PATH}"
    ERROR_LIST+=("Build manifest not found at ${MANIFEST_PATH}")
    ((ERRORS++))
fi
rm -f "$TEMP_MANIFEST"

# =============================================================================
# 4. Check SSH Key
# =============================================================================
echo -e "${YELLOW}[4/6] Checking SSH key...${NC}"
if [ -f "$ANSIBLE_SSH_KEY" ]; then
    echo -e "  ${GREEN}✓${NC} SSH key exists: ${ANSIBLE_SSH_KEY}"
else
    echo -e "  ${YELLOW}!${NC} SSH key not found: ${ANSIBLE_SSH_KEY}"
    WARNING_LIST+=("SSH key not found at ${ANSIBLE_SSH_KEY}")
    ((WARNINGS++))
fi

# =============================================================================
# 5. Check Ziti Connectivity (Warning only)
# =============================================================================
echo -e "${YELLOW}[5/6] Checking Ziti connectivity...${NC}"
if command -v ssh >/dev/null 2>&1; then
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "ansible@${SERVER_HOST}" exit 0 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Ziti connection to ${SERVER_HOST} available"
    else
        echo -e "  ${YELLOW}!${NC} Cannot connect to ${SERVER_HOST} via Ziti"
        WARNING_LIST+=("Cannot connect to ${SERVER_HOST} via Ziti - ensure ZDE is running")
        ((WARNINGS++))
    fi
else
    echo -e "  ${YELLOW}!${NC} SSH not available"
    ((WARNINGS++))
fi

# =============================================================================
# 6. Check Ansible Playbook and Role
# =============================================================================
echo -e "${YELLOW}[6/6] Checking Ansible playbook and role...${NC}"
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"
if [ -f "$ANSIBLE_DIR/deploy-web.yml" ]; then
    echo -e "  ${GREEN}✓${NC} Playbook exists: deploy-web.yml"
else
    echo -e "  ${RED}✗${NC} Playbook not found: $ANSIBLE_DIR/deploy-web.yml"
    ERROR_LIST+=("Ansible playbook deploy-web.yml not found")
    ((ERRORS++))
fi

if [ -d "$ANSIBLE_DIR/roles/theraprac-web" ]; then
    echo -e "  ${GREEN}✓${NC} Role exists: theraprac-web"
else
    echo -e "  ${RED}✗${NC} Role not found: $ANSIBLE_DIR/roles/theraprac-web"
    ERROR_LIST+=("Ansible role theraprac-web not found")
    ((ERRORS++))
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pre-flight Check Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}ERRORS (${ERRORS}):${NC}"
    for error in "${ERROR_LIST[@]}"; do
        echo -e "  ${RED}✗${NC} $error"
    done
    echo ""
fi

if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}WARNINGS (${WARNINGS}):${NC}"
    for warning in "${WARNING_LIST[@]}"; do
        echo -e "  ${YELLOW}!${NC} $warning"
    done
    echo ""
fi

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
fi

echo ""

# =============================================================================
# Prompt to Deploy
# =============================================================================

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Pre-flight checks passed (with ${WARNINGS} warnings)${NC}"
    echo ""
    
    read -p "Deploy now? [Y/n] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        echo -e "${YELLOW}Starting deployment...${NC}"
        exec "$SCRIPT_DIR/deploy-web.sh" -y
    else
        echo ""
        echo "To deploy later, run:"
        echo -e "  ${GREEN}./scripts/deploy-web.sh${NC}"
        echo ""
        echo "Or with specific parameters:"
        echo -e "  ${GREEN}./scripts/deploy-web.sh${NC} (will use cached values)"
    fi
else
    echo -e "${RED}Pre-flight checks failed with ${ERRORS} error(s)${NC}"
    echo ""
    echo "Please fix the errors above before deploying."
    exit 1
fi

