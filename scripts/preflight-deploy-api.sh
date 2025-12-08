#!/bin/bash
# =============================================================================
# Pre-flight Check for API Deployment
# =============================================================================
# Validates all prerequisites before deploying the API
#
# Usage:
#   ./scripts/preflight-deploy-api.sh <environment> <server-name> <version>
#   ./scripts/preflight-deploy-api.sh dev app.mt.dev latest
#   ./scripts/preflight-deploy-api.sh dev app.mt.dev 0.1.0
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
CACHE_FILE="$REPO_ROOT/.preflight-deploy-api-cache"

# =============================================================================
# Parse Arguments
# =============================================================================

if [ $# -lt 3 ]; then
    echo "Usage: $0 <environment> <server-name> <version>"
    echo ""
    echo "Examples:"
    echo "  $0 dev app.mt.dev latest"
    echo "  $0 dev app.mt.dev 0.1.0"
    echo ""
    echo "Environment: dev, test, prod, or nonprod"
    echo "Server name: e.g., app.mt.dev, theraprac.mt.prod"
    echo "Version: latest or semantic version (e.g., 0.1.0)"
    exit 1
fi

TARGET_ENV="$1"
SERVER_NAME="$2"
VERSION="$3"

# Validate environment
if [[ ! "$TARGET_ENV" =~ ^(dev|test|prod|nonprod)$ ]]; then
    echo -e "${RED}Error: Invalid environment '${TARGET_ENV}'${NC}"
    echo "Environment must be: dev, test, prod, or nonprod"
    exit 1
fi

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
S3_BUCKET="${S3_BUCKET:-theraprac-api}"
ANSIBLE_SSH_KEY="${ANSIBLE_SSH_KEY:-~/.ssh/id_ed25519_ansible_1}"

# Expand tilde in SSH key path
ANSIBLE_SSH_KEY="${ANSIBLE_SSH_KEY/#\~/$HOME}"

# Save provided parameters to cache (for deploy script to use later)
cat > "$CACHE_FILE" <<EOF
CACHED_SERVER_NAME="$SERVER_NAME"
CACHED_VERSION="$VERSION"
CACHED_TARGET_ENV="$TARGET_ENV"
EOF

# Derived values
SERVER_HOST="ssh.${SERVER_NAME}.ziti"
SSM_PREFIX="/theraprac/api/${TARGET_ENV}"
SECRET_NAME="theraprac/api/${TARGET_ENV}/secrets"
ZITI_DB_SERVICE="postgres.db.${TARGET_ENV}.app.ziti"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pre-flight Check for API Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Environment: ${GREEN}${TARGET_ENV}${NC}"
echo -e "Server:      ${GREEN}${SERVER_NAME}${NC}"
echo -e "Server Host: ${GREEN}${SERVER_HOST}${NC}"
echo -e "Version:     ${GREEN}${VERSION}${NC}"
echo -e "S3 Bucket:  ${GREEN}${S3_BUCKET}${NC}"
echo ""

ERRORS=0
WARNINGS=0
ERROR_LIST=()
WARNING_LIST=()

# =============================================================================
# 1. Check AWS Credentials
# =============================================================================
echo -e "${YELLOW}[1/9] Checking AWS credentials...${NC}"
if aws sts get-caller-identity --profile jfinlinson_admin >/dev/null 2>&1; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile jfinlinson_admin --query Account --output text)
    echo -e "  ${GREEN}✓${NC} AWS credentials valid (Account: ${AWS_ACCOUNT_ID})"
else
    echo -e "  ${RED}✗${NC} AWS credentials invalid or expired"
    ERRORS=$((ERRORS + 1))
    ERROR_LIST+=("AWS credentials invalid or expired")
fi
echo ""

# =============================================================================
# 2. Check SSM Parameters
# =============================================================================
echo -e "${YELLOW}[2/9] Checking SSM parameters...${NC}"
REQUIRED_SSM_PARAMS=(
    "db-host"
    "db-port"
    "db-name"
    "db-user"
    "db-admin-user"
    "db-ssl-mode"
)

for param in "${REQUIRED_SSM_PARAMS[@]}"; do
    PARAM_PATH="${SSM_PREFIX}/${param}"
    if aws ssm get-parameter --name "$PARAM_PATH" --profile jfinlinson_admin >/dev/null 2>&1; then
        VALUE=$(aws ssm get-parameter --name "$PARAM_PATH" --profile jfinlinson_admin --query 'Parameter.Value' --output text 2>/dev/null)
        echo -e "  ${GREEN}✓${NC} ${param}: ${VALUE}"
    else
        echo -e "  ${RED}✗${NC} ${param}: Missing"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("SSM parameter missing: ${param}")
    fi
done
echo ""

# =============================================================================
# 3. Check Secrets Manager
# =============================================================================
echo -e "${YELLOW}[3/9] Checking Secrets Manager...${NC}"
REQUIRED_SECRETS=("DB_ADMIN_PASSWORD" "DB_PASSWORD")

if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile jfinlinson_admin >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Secret exists: ${SECRET_NAME}"
    
    # Get and parse secrets
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --profile jfinlinson_admin --query 'SecretString' --output text 2>/dev/null)
    DB_ADMIN_PASSWORD=""
    DB_PASSWORD=""
    
    for key in "${REQUIRED_SECRETS[@]}"; do
        if echo "$SECRET_JSON" | jq -e ".${key}" >/dev/null 2>&1; then
            VALUE=$(echo "$SECRET_JSON" | jq -r ".${key}")
            if [ "$key" = "DB_ADMIN_PASSWORD" ]; then
                DB_ADMIN_PASSWORD="$VALUE"
            elif [ "$key" = "DB_PASSWORD" ]; then
                DB_PASSWORD="$VALUE"
            fi
            echo -e "  ${GREEN}✓${NC} Secret key: ${key}"
        else
            echo -e "  ${RED}✗${NC} Secret key missing: ${key}"
            ERRORS=$((ERRORS + 1))
            ERROR_LIST+=("Secrets Manager key missing: ${key}")
        fi
    done
else
    echo -e "  ${RED}✗${NC} Secret not found: ${SECRET_NAME}"
    ERRORS=$((ERRORS + 1))
    ERROR_LIST+=("Secrets Manager secret not found: ${SECRET_NAME}")
fi
echo ""

# =============================================================================
# 4. Check S3 Artifact
# =============================================================================
echo -e "${YELLOW}[4/9] Checking S3 artifact...${NC}"

# Detect version type
IS_BRANCH_BUILD=false
if [[ "$VERSION" == *"/"* ]]; then
    IS_BRANCH_BUILD=true
fi

if [ "$VERSION" = "latest" ]; then
    # Try main branch first, then check for any branch with latest
    S3_PATHS=(
        "builds/main/latest/theraprac-api-0.1.0-linux-arm64.tar.gz"
        "builds/fix/remaining-lint-errors/latest/theraprac-api-0.1.0-linux-arm64.tar.gz"
    )
    S3_PATH=""
    for path in "${S3_PATHS[@]}"; do
        if aws s3 ls "s3://${S3_BUCKET}/${path}" --profile jfinlinson_admin >/dev/null 2>&1; then
            S3_PATH="$path"
            break
        fi
    done
    if [ -z "$S3_PATH" ]; then
        echo -e "  ${RED}✗${NC} Tarball not found in expected locations"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("S3 tarball not found for version: ${VERSION}")
        echo ""
    else
        SIZE=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PATH}" --profile jfinlinson_admin --human-readable --summarize | grep "Total Size" | awk '{print $3, $4}')
        echo -e "  ${GREEN}✓${NC} Tarball exists: ${S3_PATH} (${SIZE})"
        
        # Check if tarball contains migrations
        TEMP_FILE=$(mktemp)
        aws s3 cp "s3://${S3_BUCKET}/${S3_PATH}" "$TEMP_FILE" --profile jfinlinson_admin >/dev/null 2>&1
        if tar -tzf "$TEMP_FILE" | grep -q "db/changelog/db.changelog-master.xml"; then
            MIGRATION_COUNT=$(tar -tzf "$TEMP_FILE" | grep -c "db/changelog/.*\.xml" || echo "0")
            echo -e "  ${GREEN}✓${NC} Tarball contains migrations (${MIGRATION_COUNT} files)"
        else
            echo -e "  ${RED}✗${NC} Tarball missing migrations"
            ERRORS=$((ERRORS + 1))
            ERROR_LIST+=("S3 tarball missing database migrations")
        fi
        rm -f "$TEMP_FILE"
    fi
elif [ "$IS_BRANCH_BUILD" = true ]; then
    # Branch build: builds/{branch}/{commit}/theraprac-api-{version}-linux-arm64.tar.gz
    # First, get version from manifest
    TEMP_MANIFEST=$(mktemp)
    if aws s3 cp "s3://${S3_BUCKET}/builds/${VERSION}/manifest.json" "$TEMP_MANIFEST" --profile jfinlinson_admin >/dev/null 2>&1; then
        BUILD_VERSION=$(jq -r '.version' "$TEMP_MANIFEST" 2>/dev/null || echo "0.1.0")
        S3_PATH="builds/${VERSION}/theraprac-api-${BUILD_VERSION}-linux-arm64.tar.gz"
        rm -f "$TEMP_MANIFEST"
        
        if aws s3 ls "s3://${S3_BUCKET}/${S3_PATH}" --profile jfinlinson_admin >/dev/null 2>&1; then
            SIZE=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PATH}" --profile jfinlinson_admin --human-readable --summarize | grep "Total Size" | awk '{print $3, $4}')
            echo -e "  ${GREEN}✓${NC} Tarball exists: ${S3_PATH} (${SIZE})"
            
            # Check if tarball contains migrations
            TEMP_FILE=$(mktemp)
            aws s3 cp "s3://${S3_BUCKET}/${S3_PATH}" "$TEMP_FILE" --profile jfinlinson_admin >/dev/null 2>&1
            if tar -tzf "$TEMP_FILE" | grep -q "db/changelog/db.changelog-master.xml"; then
                MIGRATION_COUNT=$(tar -tzf "$TEMP_FILE" | grep -c "db/changelog/.*\.xml" || echo "0")
                echo -e "  ${GREEN}✓${NC} Tarball contains migrations (${MIGRATION_COUNT} files)"
            else
                echo -e "  ${RED}✗${NC} Tarball missing migrations"
                ERRORS=$((ERRORS + 1))
                ERROR_LIST+=("S3 tarball missing database migrations")
            fi
            rm -f "$TEMP_FILE"
        else
            echo -e "  ${RED}✗${NC} Tarball not found: ${S3_PATH}"
            ERRORS=$((ERRORS + 1))
            ERROR_LIST+=("S3 tarball not found: ${S3_PATH}")
        fi
    else
        echo -e "  ${RED}✗${NC} Manifest not found for branch build: ${VERSION}"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("Manifest not found for branch build: ${VERSION}")
    fi
else
    # Release version - get actual version from manifest
    TEMP_MANIFEST=$(mktemp)
    if aws s3 cp "s3://${S3_BUCKET}/releases/v${VERSION}/manifest.json" "$TEMP_MANIFEST" --profile jfinlinson_admin >/dev/null 2>&1; then
        BUILD_VERSION=$(jq -r '.version' "$TEMP_MANIFEST" 2>/dev/null || echo "$VERSION")
        S3_PATH="releases/v${VERSION}/theraprac-api-${BUILD_VERSION}-linux-arm64.tar.gz"
        rm -f "$TEMP_MANIFEST"
        
        if aws s3 ls "s3://${S3_BUCKET}/${S3_PATH}" --profile jfinlinson_admin >/dev/null 2>&1; then
            SIZE=$(aws s3 ls "s3://${S3_BUCKET}/${S3_PATH}" --profile jfinlinson_admin --human-readable --summarize | grep "Total Size" | awk '{print $3, $4}')
            echo -e "  ${GREEN}✓${NC} Tarball exists: ${S3_PATH} (${SIZE})"
        else
            echo -e "  ${RED}✗${NC} Tarball not found: ${S3_PATH}"
            ERRORS=$((ERRORS + 1))
            ERROR_LIST+=("S3 tarball not found: ${S3_PATH}")
        fi
    else
        echo -e "  ${RED}✗${NC} Manifest not found for release: v${VERSION}"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("Manifest not found for release: v${VERSION}")
    fi
fi
echo ""

# =============================================================================
# 5. Check Ziti Database Service
# =============================================================================
echo -e "${YELLOW}[5/9] Checking Ziti database service...${NC}"
# Check if we can resolve and reach the service (requires ZDE running)
if ping -c 1 -W 1000 "$ZITI_DB_SERVICE" >/dev/null 2>&1; then
    # Extract IP from ping output (works on both Linux and macOS)
    IP=$(ping -c 1 -W 1000 "$ZITI_DB_SERVICE" 2>/dev/null | grep -Eo '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | head -1 | tr -d '()' || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Ziti service reachable: ${ZITI_DB_SERVICE} (${IP})"
else
    echo -e "  ${RED}✗${NC} Ziti service not reachable (ZDE may not be running): ${ZITI_DB_SERVICE}"
    ERRORS=$((ERRORS + 1))
    ERROR_LIST+=("Ziti database service not reachable: ${ZITI_DB_SERVICE}")
fi
echo ""

# =============================================================================
# 6. Check Database Connectivity (Real Test)
# =============================================================================
echo -e "${YELLOW}[6/9] Testing database connectivity...${NC}"
if [ -n "$DB_ADMIN_PASSWORD" ]; then
    DB_HOST=$(aws ssm get-parameter --name "${SSM_PREFIX}/db-host" --profile jfinlinson_admin --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    DB_PORT=$(aws ssm get-parameter --name "${SSM_PREFIX}/db-port" --profile jfinlinson_admin --query 'Parameter.Value' --output text 2>/dev/null || echo "5432")
    DB_NAME=$(aws ssm get-parameter --name "${SSM_PREFIX}/db-name" --profile jfinlinson_admin --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    DB_ADMIN_USER=$(aws ssm get-parameter --name "${SSM_PREFIX}/db-admin-user" --profile jfinlinson_admin --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    
    if [ -n "$DB_HOST" ] && [ -n "$DB_NAME" ] && [ -n "$DB_ADMIN_USER" ]; then
        echo -e "  ${GREEN}✓${NC} DB host from SSM: ${DB_HOST}"
        
        # Test connection with real query (PostgreSQL uses SELECT 1, not dual)
        if command -v psql >/dev/null 2>&1; then
            export PGPASSWORD="$DB_ADMIN_PASSWORD"
            if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} Database connection successful"
                
                # Test a more meaningful query
                RESULT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
                if [ -n "$RESULT" ] && [ "$RESULT" != "" ]; then
                    echo -e "  ${GREEN}✓${NC} Database query successful (${RESULT} tables in public schema)"
                else
                echo -e "  ${YELLOW}⚠${NC} Database query returned no results"
                WARNINGS=$((WARNINGS + 1))
                WARNING_LIST+=("Database query returned no results")
                fi
            else
        echo -e "  ${RED}✗${NC} Database connection failed"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("Database connection failed to ${DB_HOST}:${DB_PORT}")
            fi
            unset PGPASSWORD
        else
            echo -e "  ${YELLOW}⚠${NC} psql not available for connectivity test"
            WARNINGS=$((WARNINGS + 1))
            WARNING_LIST+=("psql not available for database connectivity test")
        fi
    else
        echo -e "  ${RED}✗${NC} Missing required SSM parameters for database test"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("Missing required SSM parameters for database connectivity test")
    fi
else
    echo -e "  ${RED}✗${NC} DB_ADMIN_PASSWORD not available for connectivity test"
    ERRORS=$((ERRORS + 1))
    ERROR_LIST+=("DB_ADMIN_PASSWORD not available for database connectivity test")
fi
echo ""

# =============================================================================
# 7. Check Ansible Roles
# =============================================================================
echo -e "${YELLOW}[7/9] Checking Ansible roles...${NC}"
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"

REQUIRED_ROLES=("liquibase" "theraprac-api")
for role in "${REQUIRED_ROLES[@]}"; do
    if [ -d "${ANSIBLE_DIR}/roles/${role}" ]; then
        echo -e "  ${GREEN}✓${NC} Role exists: ${role}"
    else
        echo -e "  ${RED}✗${NC} Role missing: ${role}"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("Ansible role missing: ${role}")
    fi
done

# Check playbook
if [ -f "${ANSIBLE_DIR}/deploy-api.yml" ]; then
    echo -e "  ${GREEN}✓${NC} Playbook exists: deploy-api.yml"
else
    echo -e "  ${RED}✗${NC} Playbook missing: deploy-api.yml"
    ERRORS=$((ERRORS + 1))
    ERROR_LIST+=("Ansible playbook missing: deploy-api.yml")
fi
echo ""

# =============================================================================
# 8. Check Target Server
# =============================================================================
echo -e "${YELLOW}[8/9] Checking target server configuration...${NC}"
# Check if server is in inventory
if grep -q "${SERVER_NAME//./-}" "${ANSIBLE_DIR}/inventory/ziti.yml" 2>/dev/null || \
   grep -q "${SERVER_NAME}" "${ANSIBLE_DIR}/inventory/ziti.yml" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Server found in inventory"
else
    echo -e "  ${YELLOW}⚠${NC} Server not in inventory (will use server name directly): ${SERVER_NAME}"
    WARNINGS=$((WARNINGS + 1))
    WARNING_LIST+=("Server not in Ansible inventory: ${SERVER_NAME}")
fi

# Check if SSH key exists
if [ -f "$ANSIBLE_SSH_KEY" ]; then
    echo -e "  ${GREEN}✓${NC} Ansible SSH key exists: ${ANSIBLE_SSH_KEY}"
else
    echo -e "  ${RED}✗${NC} Ansible SSH key not found: ${ANSIBLE_SSH_KEY}"
    ERRORS=$((ERRORS + 1))
    ERROR_LIST+=("Ansible SSH key not found: ${ANSIBLE_SSH_KEY}")
fi

# Check server host reachability
if ping -c 1 -W 1000 "${SERVER_HOST}" >/dev/null 2>&1; then
    IP=$(ping -c 1 -W 1000 "${SERVER_HOST}" 2>/dev/null | grep -Eo '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | head -1 | tr -d '()' || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Server host reachable: ${SERVER_HOST} (${IP})"
    
    # Test SSH connectivity with Ansible key
    if ssh -i "$ANSIBLE_SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "ansible@${SERVER_HOST}" "echo 'SSH test successful'" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} SSH connectivity successful with Ansible key"
    else
        echo -e "  ${RED}✗${NC} SSH connectivity failed with Ansible key"
        ERRORS=$((ERRORS + 1))
        ERROR_LIST+=("SSH connectivity failed to ${SERVER_HOST} with Ansible key")
    fi
else
    echo -e "  ${RED}✗${NC} Server host not reachable (ZDE may not be running): ${SERVER_HOST}"
    ERRORS=$((ERRORS + 1))
    ERROR_LIST+=("Server host not reachable: ${SERVER_HOST}")
fi
echo ""

# =============================================================================
# 9. Check Liquibase Availability
# =============================================================================
echo -e "${YELLOW}[9/9] Checking Liquibase on target server...${NC}"
if ssh -i "$ANSIBLE_SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "ansible@${SERVER_HOST}" "which liquibase >/dev/null 2>&1 || test -f /usr/local/bin/liquibase" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Liquibase available on target server"
else
    echo -e "  ${YELLOW}⚠${NC} Liquibase not found on server (will be installed during deployment)"
    WARNINGS=$((WARNINGS + 1))
    WARNING_LIST+=("Liquibase not found on server (will be installed during deployment)")
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pre-flight Check Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Display errors if any
if [ ${#ERROR_LIST[@]} -gt 0 ]; then
    echo -e "${RED}Errors (${#ERROR_LIST[@]}):${NC}"
    for i in "${!ERROR_LIST[@]}"; do
        echo -e "  ${RED}✗${NC} ${ERROR_LIST[$i]}"
    done
    echo ""
fi

# Display warnings if any
if [ ${#WARNING_LIST[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warnings (${#WARNING_LIST[@]}):${NC}"
    for i in "${!WARNING_LIST[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} ${WARNING_LIST[$i]}"
    done
    echo ""
fi

# Final status and deploy prompt
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Ready to deploy.${NC}"
    echo ""
    read -p "Deploy now? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        echo -e "${BLUE}Running deployment...${NC}"
        echo ""
        DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-api.sh"
        if [ -f "$DEPLOY_SCRIPT" ]; then
            # Save to deploy script's cache file so it picks it up
            DEPLOY_CACHE_FILE="$REPO_ROOT/.deploy-api-cache"
            echo "CACHED_VERSION=\"$VERSION\"" > "$DEPLOY_CACHE_FILE"
            echo "CACHED_SERVER_NAME=\"$SERVER_NAME\"" >> "$DEPLOY_CACHE_FILE"
            echo "CACHED_S3_BUCKET=\"theraprac-api\"" >> "$DEPLOY_CACHE_FILE"
            
            # Run deploy script in non-interactive mode (it will use cached values)
            cd "$REPO_ROOT"
            "$DEPLOY_SCRIPT" --non-interactive
        else
            echo -e "${RED}Error: Deploy script not found: ${DEPLOY_SCRIPT}${NC}"
            exit 1
        fi
    else
        echo ""
        echo -e "${YELLOW}Deployment cancelled. Run manually with:${NC}"
        echo -e "  ${GREEN}./scripts/deploy-api.sh${NC}"
        echo -e "${YELLOW}Then enter: ${TARGET_ENV}, ${SERVER_NAME}, ${VERSION}${NC}"
    fi
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ ${WARNINGS} warning(s) found, but no errors.${NC}"
    echo -e "${YELLOW}Deployment can proceed, but review warnings above.${NC}"
    echo ""
    read -p "Proceed with deployment? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${BLUE}Running deployment...${NC}"
        echo ""
        DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-api.sh"
        if [ -f "$DEPLOY_SCRIPT" ]; then
            # Save to deploy script's cache file so it picks it up
            DEPLOY_CACHE_FILE="$REPO_ROOT/.deploy-api-cache"
            echo "CACHED_VERSION=\"$VERSION\"" > "$DEPLOY_CACHE_FILE"
            echo "CACHED_SERVER_NAME=\"$SERVER_NAME\"" >> "$DEPLOY_CACHE_FILE"
            echo "CACHED_S3_BUCKET=\"theraprac-api\"" >> "$DEPLOY_CACHE_FILE"
            
            # Run deploy script in non-interactive mode (it will use cached values)
            cd "$REPO_ROOT"
            "$DEPLOY_SCRIPT" --non-interactive
        else
            echo -e "${RED}Error: Deploy script not found: ${DEPLOY_SCRIPT}${NC}"
            exit 1
        fi
    else
        echo ""
        echo -e "${YELLOW}Deployment cancelled. Run manually with:${NC}"
        echo -e "  ${GREEN}./scripts/deploy-api.sh${NC}"
        echo -e "${YELLOW}Then enter: ${TARGET_ENV}, ${SERVER_NAME}, ${VERSION}${NC}"
    fi
    exit 0
else
    echo -e "${RED}✗ ${ERRORS} error(s) and ${WARNINGS} warning(s) found.${NC}"
    echo -e "${RED}Please fix errors before deploying.${NC}"
    exit 1
fi
