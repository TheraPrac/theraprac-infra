#!/bin/bash
# =============================================================================
# List Ziti Identities with Role Attributes
# =============================================================================
# Quick script to list all identities and their roles
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get admin password from Secrets Manager
ZITI_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id ziti/nonprod/admin-password \
    --query 'SecretString' \
    --output text \
    --region us-west-2)

# Login to Ziti controller
echo "$ZITI_PASSWORD" | ziti edge login "https://ziti-nonprod.theraprac.com:443" \
    --username admin \
    --password - \
    --yes > /dev/null 2>&1

echo -e "${CYAN}=== Ziti Identities ===${NC}"
echo ""
echo -e "${CYAN}Name${NC} | ${CYAN}Type${NC} | ${CYAN}Role Attributes${NC}"
echo "----------------------------------------"

ziti edge list identities --output-json 2>/dev/null | jq -r '.data[] | "\(.name)|\(.type)|\(.roleAttributes | join(","))"' | while IFS='|' read -r name type roles; do
    echo -e "${GREEN}$name${NC} | $type | $roles"
done

