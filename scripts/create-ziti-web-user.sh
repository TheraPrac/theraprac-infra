#!/bin/bash
# =============================================================================
# Create Ziti User for Dev Environment Web Access
# =============================================================================
# Creates a new Ziti identity with web-only access to the dev environment.
# The identity will have the 'users' role attribute, which grants access to
# web services (app-dev.theraprac.com) via the https-web-dial policy.
#
# Usage:
#   ./scripts/create-ziti-web-user.sh <identity-name>
#
# Example:
#   ./scripts/create-ziti-web-user.sh jane-dev
#
# Output:
#   - Creates <identity-name>.jwt in the current directory
#   - User enrolls with: ziti edge enroll <identity-name>.jwt
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
ZITI_PUBLIC_ENDPOINT="ziti-nonprod.theraprac.com"
ZITI_CONTROLLER_PORT="443"
ZITI_ADMIN_USER="admin"
ZITI_SECRETS_MANAGER_PATH="ziti/nonprod/admin-password"
ZITI_ROLE_ATTRIBUTES="users"  # Web-only access role

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Print usage
usage() {
    echo "Usage: $0 <identity-name>"
    echo ""
    echo "Creates a new Ziti identity with web-only access to the dev environment."
    echo ""
    echo "Arguments:"
    echo "  identity-name    Name of the identity to create (e.g., jane-dev)"
    echo ""
    echo "Example:"
    echo "  $0 jane-dev"
    echo ""
    exit 1
}

# Validate arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Identity name is required${NC}"
    echo ""
    usage
fi

IDENTITY_NAME="$1"

# Validate identity name format (alphanumeric, dash, underscore)
if ! [[ "$IDENTITY_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}Error: Identity name must contain only alphanumeric characters, dashes, and underscores${NC}"
    exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Create Ziti User - Dev Environment Web Access            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Identity Name:${NC} $IDENTITY_NAME"
echo -e "${BLUE}Role Attributes:${NC} $ZITI_ROLE_ATTRIBUTES"
echo -e "${BLUE}Access:${NC} Dev environment web and API services"
echo ""

# Check if ziti CLI is available
if ! command -v ziti &> /dev/null; then
    echo -e "${RED}Error: 'ziti' command not found${NC}"
    echo "Please install the Ziti CLI: https://openziti.io/docs/core-tools/cli-installation"
    exit 1
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: 'aws' command not found${NC}"
    echo "Please install the AWS CLI"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${YELLOW}Warning: AWS credentials not configured or expired${NC}"
    echo "Attempting to use default profile..."
    export AWS_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"
fi

# Get admin password from Secrets Manager
echo -e "${BLUE}Retrieving Ziti admin password from AWS Secrets Manager...${NC}"
ZITI_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$ZITI_SECRETS_MANAGER_PATH" \
    --query 'SecretString' \
    --output text \
    --region us-west-2 2>/dev/null) || {
    echo -e "${RED}Error: Failed to retrieve admin password from Secrets Manager${NC}"
    echo "Secret path: $ZITI_SECRETS_MANAGER_PATH"
    echo "Please ensure AWS credentials are configured and the secret exists."
    exit 1
}

if [ -z "$ZITI_PASSWORD" ]; then
    echo -e "${RED}Error: Admin password is empty${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Password retrieved${NC}"
echo ""

# Login to Ziti controller
echo -e "${BLUE}Logging in to Ziti controller...${NC}"
echo "$ZITI_PASSWORD" | ziti edge login "https://${ZITI_PUBLIC_ENDPOINT}:${ZITI_CONTROLLER_PORT}" \
    --username "$ZITI_ADMIN_USER" \
    --password - \
    --yes > /dev/null 2>&1 || {
    echo -e "${RED}Error: Failed to login to Ziti controller${NC}"
    echo "Endpoint: https://${ZITI_PUBLIC_ENDPOINT}:${ZITI_CONTROLLER_PORT}"
    exit 1
}

echo -e "${GREEN}✓ Logged in successfully${NC}"
echo ""

# Check if identity already exists
echo -e "${BLUE}Checking if identity already exists...${NC}"
IDENTITY_COUNT=$(ziti edge list identities "name=\"${IDENTITY_NAME}\"" --output-json 2>/dev/null | jq -r '.data | length' 2>/dev/null || echo "0")

if [ "$IDENTITY_COUNT" -gt 0 ]; then
    echo -e "${RED}Error: Identity '${IDENTITY_NAME}' already exists${NC}"
    echo ""
    echo "To remove the existing identity:"
    echo "  ziti edge delete identity ${IDENTITY_NAME}"
    echo ""
    echo "Or use a different identity name."
    exit 1
fi

echo -e "${GREEN}✓ Identity name is available${NC}"
echo ""

# Create identity with role attributes
echo -e "${BLUE}Creating identity with role attributes...${NC}"
JWT_FILE="${REPO_ROOT}/${IDENTITY_NAME}.jwt"

ziti edge create identity "$IDENTITY_NAME" \
    --role-attributes "$ZITI_ROLE_ATTRIBUTES" \
    -o "$JWT_FILE" || {
    echo -e "${RED}Error: Failed to create identity${NC}"
    exit 1
}

if [ ! -f "$JWT_FILE" ]; then
    echo -e "${RED}Error: JWT file was not created${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Identity created successfully${NC}"
echo ""

# Display success message
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Identity Created Successfully                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Identity Details:${NC}"
echo -e "  ${BLUE}Name:${NC} $IDENTITY_NAME"
echo -e "  ${BLUE}Role Attributes:${NC} $ZITI_ROLE_ATTRIBUTES"
echo -e "  ${BLUE}JWT File:${NC} $JWT_FILE"
echo ""
echo -e "${CYAN}Access Granted:${NC}"
echo -e "  • Dev environment web application: ${GREEN}https://app-dev.theraprac.com${NC}"
echo -e "  • Dev environment API: ${GREEN}https://api-dev.theraprac.com${NC}"
echo ""
echo -e "${CYAN}Next Steps - Enrollment:${NC}"
echo ""
echo -e "${YELLOW}Option 1: Ziti CLI Enrollment${NC}"
echo "  1. Copy the JWT file to the user's machine:"
echo "     ${BLUE}scp $JWT_FILE user@machine:~/${NC}"
echo ""
echo "  2. On the user's machine, enroll the identity:"
echo "     ${BLUE}ziti edge enroll $JWT_FILE -o ~/.config/ziti/identities/${IDENTITY_NAME}.json${NC}"
echo ""
echo -e "${YELLOW}Option 2: Ziti Desktop Edge (ZDE) Enrollment${NC}"
echo "  1. Open Ziti Desktop Edge application"
echo "  2. Click 'Add Identity' or '+' button"
echo "  3. Select 'Import from File'"
echo "  4. Choose the JWT file: ${BLUE}$JWT_FILE${NC}"
echo "  5. The identity will be enrolled and ready to use"
echo ""
echo -e "${CYAN}Testing Access:${NC}"
echo "  Once enrolled, the user can access:"
echo "    ${GREEN}https://app-dev.theraprac.com${NC} (web application)"
echo "    ${GREEN}https://api-dev.theraprac.com${NC} (API - required for web app)"
echo ""
echo -e "${YELLOW}Note:${NC} This identity has web and API access for the dev environment. It does NOT have:"
echo "  • SSH access to servers"
echo "  • Database access"
echo "  • Access to test or production environments"
echo ""
echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""

