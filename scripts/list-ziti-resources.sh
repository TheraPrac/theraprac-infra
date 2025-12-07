#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - List Ziti Resources
# =============================================================================
# Lists all Ziti identities, services, configs, and policies for review.
# Useful for auditing what's currently configured in Ziti.
#
# Usage:
#   ./scripts/list-ziti-resources.sh
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

# Default values
ZITI_ENDPOINT="${ZITI_ENDPOINT:-ziti-nonprod.theraprac.com}"
ZITI_PORT="${ZITI_PORT:-443}"
ZITI_SECRET_PATH="${ZITI_SECRET_PATH:-ziti/nonprod/admin-password}"
AWS_REGION="${AWS_REGION:-us-west-2}"

echo -e "${BLUE}=== TheraPrac Ziti Resource Audit ===${NC}"
echo ""

# Check if ziti CLI is available
if ! command -v ziti &> /dev/null; then
    echo -e "${RED}Error: ziti CLI not found in PATH${NC}"
    echo "Please install the Ziti CLI: https://openziti.io/docs/core-concepts/clients/cli"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq not found in PATH${NC}"
    echo "Please install jq: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Get admin password from Secrets Manager
echo -e "${CYAN}Fetching Ziti admin password from Secrets Manager...${NC}"
ZITI_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$ZITI_SECRET_PATH" \
    --query 'SecretString' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ -z "$ZITI_PASSWORD" ]; then
    echo -e "${RED}Error: Failed to retrieve Ziti admin password from Secrets Manager${NC}"
    exit 1
fi

# Login to Ziti controller
echo -e "${CYAN}Logging in to Ziti controller...${NC}"
echo "$ZITI_PASSWORD" | ziti edge login "https://${ZITI_ENDPOINT}:${ZITI_PORT}" \
    --username admin \
    --password - \
    --yes > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to login to Ziti controller${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Connected to Ziti controller${NC}"
echo ""

# =============================================================================
# List Identities
# =============================================================================

echo -e "${BLUE}=== Identities ===${NC}"
IDENTITIES=$(ziti edge list identities --output-json 2>/dev/null | jq -r '.data[] | "\(.name)|\(.type)|\(.roleAttributes | join(","))"')

if [ -z "$IDENTITIES" ]; then
    echo -e "${YELLOW}No identities found${NC}"
else
    echo -e "${CYAN}Name${NC} | ${CYAN}Type${NC} | ${CYAN}Role Attributes${NC}"
    echo "----------------------------------------"
    echo "$IDENTITIES" | while IFS='|' read -r name type roles; do
        echo -e "${GREEN}$name${NC} | $type | $roles"
    done
fi
echo ""

# =============================================================================
# List Services
# =============================================================================

echo -e "${BLUE}=== Services ===${NC}"
SERVICES=$(ziti edge list services --output-json 2>/dev/null | jq -r '.data[] | "\(.name)|\(.roleAttributes | join(","))"')

if [ -z "$SERVICES" ]; then
    echo -e "${YELLOW}No services found${NC}"
else
    echo -e "${CYAN}Name${NC} | ${CYAN}Role Attributes${NC}"
    echo "----------------------------------------"
    echo "$SERVICES" | while IFS='|' read -r name roles; do
        echo -e "${GREEN}$name${NC} | $roles"
    done
fi
echo ""

# =============================================================================
# List Configs
# =============================================================================

echo -e "${BLUE}=== Configs ===${NC}"
CONFIGS=$(ziti edge list configs --output-json 2>/dev/null | jq -r '.data[] | "\(.name)|\(.configType)"')

if [ -z "$CONFIGS" ]; then
    echo -e "${YELLOW}No configs found${NC}"
else
    echo -e "${CYAN}Name${NC} | ${CYAN}Type${NC}"
    echo "----------------------------------------"
    echo "$CONFIGS" | while IFS='|' read -r name type; do
        echo -e "${GREEN}$name${NC} | $type"
    done
fi
echo ""

# =============================================================================
# List Service Policies
# =============================================================================

echo -e "${BLUE}=== Service Policies ===${NC}"
POLICIES=$(ziti edge list service-policies --output-json 2>/dev/null | jq -r '.data[] | "\(.name)|\(.semantic)|\(.serviceRoles | join(","))|\(.identityRoles | join(","))"')

if [ -z "$POLICIES" ]; then
    echo -e "${YELLOW}No service policies found${NC}"
else
    echo -e "${CYAN}Name${NC} | ${CYAN}Semantic${NC} | ${CYAN}Service Roles${NC} | ${CYAN}Identity Roles${NC}"
    echo "----------------------------------------"
    echo "$POLICIES" | while IFS='|' read -r name semantic service_roles identity_roles; do
        echo -e "${GREEN}$name${NC} | $semantic | $service_roles | $identity_roles"
    done
fi
echo ""

# =============================================================================
# List Service Edge Router Policies
# =============================================================================

echo -e "${BLUE}=== Service Edge Router Policies ===${NC}"
SERPS=$(ziti edge list service-edge-router-policies --output-json 2>/dev/null | jq -r '.data[] | "\(.name)|\(.serviceRoles | join(","))|\(.edgeRouterRoles | join(","))"')

if [ -z "$SERPS" ]; then
    echo -e "${YELLOW}No service edge router policies found${NC}"
else
    echo -e "${CYAN}Name${NC} | ${CYAN}Service Roles${NC} | ${CYAN}Edge Router Roles${NC}"
    echo "----------------------------------------"
    echo "$SERPS" | while IFS='|' read -r name service_roles router_roles; do
        echo -e "${GREEN}$name${NC} | $service_roles | $router_roles"
    done
fi
echo ""

# =============================================================================
# Summary
# =============================================================================

IDENTITY_COUNT=$(echo "$IDENTITIES" | grep -c . || echo "0")
SERVICE_COUNT=$(echo "$SERVICES" | grep -c . || echo "0")
CONFIG_COUNT=$(echo "$CONFIGS" | grep -c . || echo "0")
POLICY_COUNT=$(echo "$POLICIES" | grep -c . || echo "0")
SERP_COUNT=$(echo "$SERPS" | grep -c . || echo "0")

echo -e "${BLUE}=== Summary ===${NC}"
echo "Identities: $IDENTITY_COUNT"
echo "Services: $SERVICE_COUNT"
echo "Configs: $CONFIG_COUNT"
echo "Service Policies: $POLICY_COUNT"
echo "Service Edge Router Policies: $SERP_COUNT"
echo ""

# Check for basic-server identities
BASIC_SERVER_IDENTITIES=$(echo "$IDENTITIES" | grep "^basic-server-" || true)
if [ -n "$BASIC_SERVER_IDENTITIES" ]; then
    echo -e "${YELLOW}⚠ Basic Server Identities Found:${NC}"
    echo "$BASIC_SERVER_IDENTITIES" | while IFS='|' read -r name type roles; do
        echo "  - $name"
    done
    echo ""
    echo -e "${YELLOW}Note: These should be cleaned up before destroying servers with Terraform${NC}"
    echo ""
fi

echo -e "${GREEN}✓ Audit complete${NC}"

