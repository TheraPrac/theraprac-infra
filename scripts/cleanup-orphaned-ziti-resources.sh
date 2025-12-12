#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Ziti Orphaned Resource Cleanup Script
# =============================================================================
# Safely removes orphaned Ziti resources identified by the audit script.
# This script is interactive and requires confirmation before deleting anything.
#
# Usage:
#   ./scripts/cleanup-orphaned-ziti-resources.sh [environment] [--dry-run]
#   ./scripts/cleanup-orphaned-ziti-resources.sh nonprod
#   ./scripts/cleanup-orphaned-ziti-resources.sh nonprod --dry-run
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

# Parse arguments
ENVIRONMENT="${1:-nonprod}"
DRY_RUN=false

if [ "$2" = "--dry-run" ]; then
    DRY_RUN=true
fi

# Default values
ZITI_ENDPOINT="${ZITI_ENDPOINT:-ziti-${ENVIRONMENT}.theraprac.com}"
ZITI_PORT="${ZITI_PORT:-443}"
ZITI_SECRET_PATH="${ZITI_SECRET_PATH:-ziti/${ENVIRONMENT}/admin-password}"
AWS_REGION="${AWS_REGION:-us-west-2}"

echo -e "${BLUE}=== TheraPrac Ziti Orphaned Resource Cleanup ===${NC}"
echo -e "Environment: ${CYAN}${ENVIRONMENT}${NC}"
echo -e "Controller: ${CYAN}${ZITI_ENDPOINT}${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "Mode: ${YELLOW}DRY RUN (no changes will be made)${NC}"
fi
echo ""

# Check if ziti CLI is available
if ! command -v ziti &> /dev/null; then
    echo -e "${RED}Error: ziti CLI not found in PATH${NC}"
    exit 1
fi

# Login to Ziti
echo -e "${CYAN}Fetching Ziti admin password from Secrets Manager...${NC}"
ZITI_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$ZITI_SECRET_PATH" \
    --query 'SecretString' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ -z "$ZITI_PASSWORD" ]; then
    echo -e "${RED}Error: Failed to retrieve Ziti admin password${NC}"
    exit 1
fi

echo -e "${CYAN}Logging in to Ziti controller...${NC}"
echo "$ZITI_PASSWORD" | ziti edge login "https://${ZITI_ENDPOINT}:${ZITI_PORT}" \
    --username admin \
    --password - \
    --yes > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to login to Ziti controller${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Connected${NC}"
echo ""

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_orphaned_configs() {
    echo -e "${BLUE}=== Checking for Orphaned Configs ===${NC}"
    
    local configs=$(ziti edge list configs --output-json 2>/dev/null | jq -r '.data[]')
    local services=$(ziti edge list services --output-json 2>/dev/null | jq -r '.data[]')
    
    local orphaned_count=0
    
    while IFS= read -r config; do
        local config_id=$(echo "$config" | jq -r '.id')
        local config_name=$(echo "$config" | jq -r '.name')
        
        # Check if config is referenced by any service
        local referenced=$(echo "$services" | jq -r "select(.configs // [] | contains([\"$config_id\"])) | .name")
        
        if [ -z "$referenced" ]; then
            echo -e "${YELLOW}  Orphaned config: $config_name${NC}"
            orphaned_count=$((orphaned_count + 1))
            
            if [ "$DRY_RUN" = false ]; then
                read -p "    Delete this config? [y/N] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    if ziti edge delete config "$config_name" 2>/dev/null; then
                        echo -e "${GREEN}    ✓ Deleted${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete${NC}"
                    fi
                fi
            fi
        fi
    done <<< "$configs"
    
    if [ $orphaned_count -eq 0 ]; then
        echo -e "${GREEN}  No orphaned configs found${NC}"
    fi
    echo ""
}

cleanup_orphaned_terminators() {
    echo -e "${BLUE}=== Checking for Orphaned Terminators ===${NC}"
    
    local terminators=$(ziti edge list terminators --output-json 2>/dev/null | jq -r '.data[]')
    local services=$(ziti edge list services --output-json 2>/dev/null | jq -r '.data[] | {id, name}')
    local routers=$(ziti edge list edge-routers --output-json 2>/dev/null | jq -r '.data[] | {id, name}')
    
    local orphaned_count=0
    
    while IFS= read -r terminator; do
        local terminator_id=$(echo "$terminator" | jq -r '.id')
        local service_id=$(echo "$terminator" | jq -r '.service')
        local router_id=$(echo "$terminator" | jq -r '.router')
        
        local service_exists=$(echo "$services" | jq -r "select(.id == \"$service_id\") | .name")
        local router_exists=$(echo "$routers" | jq -r "select(.id == \"$router_id\") | .name")
        
        if [ -z "$service_exists" ] || [ -z "$router_exists" ]; then
            echo -e "${YELLOW}  Orphaned terminator: $terminator_id${NC}"
            if [ -z "$service_exists" ]; then
                echo -e "    Service ID $service_id does not exist"
            fi
            if [ -z "$router_exists" ]; then
                echo -e "    Router ID $router_id does not exist"
            fi
            orphaned_count=$((orphaned_count + 1))
            
            if [ "$DRY_RUN" = false ]; then
                read -p "    Delete this terminator? [y/N] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    if ziti edge delete terminator "$terminator_id" 2>/dev/null; then
                        echo -e "${GREEN}    ✓ Deleted${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete${NC}"
                    fi
                fi
            fi
        fi
    done <<< "$terminators"
    
    if [ $orphaned_count -eq 0 ]; then
        echo -e "${GREEN}  No orphaned terminators found${NC}"
    fi
    echo ""
}

cleanup_basic_server_resources() {
    echo -e "${BLUE}=== Checking for Orphaned Basic Server Resources ===${NC}"
    
    local identities=$(ziti edge list identities --output-json 2>/dev/null | jq -r '.data[] | select(.name | startswith("basic-server-"))')
    
    if [ -z "$identities" ]; then
        echo -e "${GREEN}  No basic-server identities found${NC}"
        echo ""
        return
    fi
    
    echo -e "${CYAN}Found basic-server identities. Review each one:${NC}"
    echo ""
    
    while IFS= read -r identity; do
        local identity_name=$(echo "$identity" | jq -r '.name')
        local identity_id=$(echo "$identity" | jq -r '.id')
        
        echo -e "${YELLOW}Identity: $identity_name${NC}"
        
        # Check for related services (matching pattern)
        local server_pattern=$(echo "$identity_name" | sed 's/^basic-server-//' | sed 's/-/./g')
        local related_services=$(ziti edge list services --output-json 2>/dev/null | \
            jq -r ".data[] | select(.name | contains(\"$server_pattern\")) | .name")
        
        # Check for active sessions
        local active_sessions=$(ziti edge list sessions --output-json 2>/dev/null | \
            jq -r ".data[] | select(.identityId == \"$identity_id\") | .id" | wc -l)
        
        echo "  Related services: $(echo "$related_services" | wc -l | tr -d ' ')"
        echo "  Active sessions: $active_sessions"
        
        if [ -z "$related_services" ] && [ "$active_sessions" -eq 0 ]; then
            echo -e "  ${YELLOW}⚠ Appears orphaned${NC}"
            
            if [ "$DRY_RUN" = false ]; then
                read -p "  Delete this identity and related resources? [y/N] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    # Delete related services first
                    if [ -n "$related_services" ]; then
                        while IFS= read -r service_name; do
                            echo "    Deleting service: $service_name"
                            ziti edge delete service "$service_name" 2>/dev/null || true
                            ziti edge delete config "${service_name}.host" 2>/dev/null || true
                            ziti edge delete config "${service_name}.intercept" 2>/dev/null || true
                            ziti edge delete service-policy "${service_name}-bind" 2>/dev/null || true
                        done <<< "$related_services"
                    fi
                    
                    # Delete identity
                    if ziti edge delete identity "$identity_name" 2>/dev/null; then
                        echo -e "${GREEN}    ✓ Deleted identity${NC}"
                    else
                        echo -e "${RED}    ✗ Failed to delete identity${NC}"
                    fi
                fi
            fi
        else
            echo -e "  ${GREEN}✓ Has active resources${NC}"
        fi
        echo ""
    done <<< "$identities"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    if [ "$DRY_RUN" = false ]; then
        echo -e "${YELLOW}⚠ WARNING: This script will delete Ziti resources.${NC}"
        echo -e "${YELLOW}⚠ Make sure you've reviewed the audit output first.${NC}"
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled"
            exit 0
        fi
        echo ""
    fi
    
    cleanup_orphaned_configs
    cleanup_orphaned_terminators
    cleanup_basic_server_resources
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
    echo ""
    echo -e "${CYAN}Recommendation: Run the audit script again to verify cleanup:${NC}"
    echo "  ./scripts/audit-ziti-resources.sh $ENVIRONMENT"
    echo ""
}

main



