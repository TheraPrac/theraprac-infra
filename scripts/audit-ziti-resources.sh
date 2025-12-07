#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Ziti Resource Audit Script
# =============================================================================
# Comprehensive audit of Ziti resources to identify:
#   - Orphaned resources (dangling references)
#   - Resources that should be cleaned up
#   - Unused resources
#   - Policy inconsistencies
#
# Usage:
#   ./scripts/audit-ziti-resources.sh [environment]
#   ./scripts/audit-ziti-resources.sh nonprod
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
ENVIRONMENT="${1:-nonprod}"
ZITI_ENDPOINT="${ZITI_ENDPOINT:-ziti-${ENVIRONMENT}.theraprac.com}"
ZITI_PORT="${ZITI_PORT:-443}"
ZITI_SECRET_PATH="${ZITI_SECRET_PATH:-ziti/${ENVIRONMENT}/admin-password}"
AWS_REGION="${AWS_REGION:-us-west-2}"

# Temporary files for JSON data
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

IDENTITIES_FILE="$TMP_DIR/identities.json"
SERVICES_FILE="$TMP_DIR/services.json"
CONFIGS_FILE="$TMP_DIR/configs.json"
SERVICE_POLICIES_FILE="$TMP_DIR/service-policies.json"
EDGE_ROUTER_POLICIES_FILE="$TMP_DIR/edge-router-policies.json"
SERVICE_EDGE_ROUTER_POLICIES_FILE="$TMP_DIR/service-edge-router-policies.json"
TERMINATORS_FILE="$TMP_DIR/terminators.json"
EDGE_ROUTERS_FILE="$TMP_DIR/edge-routers.json"
SESSIONS_FILE="$TMP_DIR/sessions.json"

# Issue tracking
ISSUES=()
WARNINGS=()
INFO=()

echo -e "${BLUE}=== TheraPrac Ziti Resource Audit ===${NC}"
echo -e "Environment: ${CYAN}${ENVIRONMENT}${NC}"
echo -e "Controller: ${CYAN}${ZITI_ENDPOINT}${NC}"
echo ""

# =============================================================================
# Helper Functions
# =============================================================================

check_ziti_cli() {
    if ! command -v ziti &> /dev/null; then
        echo -e "${RED}Error: ziti CLI not found in PATH${NC}"
        echo "Please install the Ziti CLI: https://openziti.io/docs/core-concepts/clients/cli"
        exit 1
    fi
}

login_ziti() {
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

    echo -e "${CYAN}Logging in to Ziti controller...${NC}"
    ziti edge login "https://${ZITI_ENDPOINT}:${ZITI_PORT}" \
        --username admin \
        --password "$ZITI_PASSWORD" \
        --yes > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to login to Ziti controller${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Connected to Ziti controller${NC}"
    echo ""
}

fetch_resources() {
    echo -e "${CYAN}Fetching Ziti resources...${NC}"
    
    ziti edge list identities --output-json > "$IDENTITIES_FILE" 2>/dev/null
    ziti edge list services --output-json > "$SERVICES_FILE" 2>/dev/null
    ziti edge list configs --output-json > "$CONFIGS_FILE" 2>/dev/null
    ziti edge list service-policies --output-json > "$SERVICE_POLICIES_FILE" 2>/dev/null
    ziti edge list edge-router-policies --output-json > "$EDGE_ROUTER_POLICIES_FILE" 2>/dev/null
    ziti edge list service-edge-router-policies --output-json > "$SERVICE_EDGE_ROUTER_POLICIES_FILE" 2>/dev/null
    ziti edge list terminators --output-json > "$TERMINATORS_FILE" 2>/dev/null
    ziti edge list edge-routers --output-json > "$EDGE_ROUTERS_FILE" 2>/dev/null
    ziti edge list sessions --output-json > "$SESSIONS_FILE" 2>/dev/null
    
    echo -e "${GREEN}✓ Resources fetched${NC}"
    echo ""
}

# =============================================================================
# Audit Functions
# =============================================================================

audit_orphaned_services() {
    echo -e "${BLUE}=== Auditing Services ===${NC}"
    
    local service_count=$(jq -r '.data | length' "$SERVICES_FILE")
    echo -e "Total services: ${CYAN}${service_count}${NC}"
    
    # Check for services without configs
    while IFS= read -r service; do
        local service_name=$(echo "$service" | jq -r '.name')
        local service_id=$(echo "$service" | jq -r '.id')
        local configs=$(echo "$service" | jq -r '.configs // [] | length')
        
        if [ "$configs" = "0" ]; then
            ISSUES+=("Service '$service_name' has no configs attached")
        fi
        
        # Check if configs exist
        local service_configs=$(echo "$service" | jq -r '.configs // [] | .[]')
        for config_id in $service_configs; do
            local config_exists=$(jq -r ".data[] | select(.id == \"$config_id\") | .name" "$CONFIGS_FILE")
            if [ -z "$config_exists" ]; then
                ISSUES+=("Service '$service_name' references non-existent config ID: $config_id")
            fi
        done
    done < <(jq -c '.data[]' "$SERVICES_FILE")
    
    echo ""
}

audit_orphaned_configs() {
    echo -e "${BLUE}=== Auditing Configs ===${NC}"
    
    local config_count=$(jq -r '.data | length' "$CONFIGS_FILE")
    echo -e "Total configs: ${CYAN}${config_count}${NC}"
    
    # Check for configs not referenced by any service
    while IFS= read -r config; do
        local config_id=$(echo "$config" | jq -r '.id')
        local config_name=$(echo "$config" | jq -r '.name')
        
        local referenced=$(jq -r ".data[] | select(.configs // [] | contains([\"$config_id\"])) | .name" "$SERVICES_FILE")
        if [ -z "$referenced" ]; then
            WARNINGS+=("Config '$config_name' is not referenced by any service")
        fi
    done < <(jq -c '.data[]' "$CONFIGS_FILE")
    
    echo ""
}

audit_service_policies() {
    echo -e "${BLUE}=== Auditing Service Policies ===${NC}"
    
    local policy_count=$(jq -r '.data | length' "$SERVICE_POLICIES_FILE")
    echo -e "Total service policies: ${CYAN}${policy_count}${NC}"
    
    while IFS= read -r policy; do
        local policy_name=$(echo "$policy" | jq -r '.name')
        local service_roles=$(echo "$policy" | jq -r '.serviceRoles // [] | .[]')
        local identity_roles=$(echo "$policy" | jq -r '.identityRoles // [] | .[]')
        
        # Check if service roles match any services
        if [ -n "$service_roles" ]; then
            local matching_services=$(jq -r ".data[] | select(.roleAttributes // [] | any(. as \$r | (\"$service_roles\" | split(\",\") | .[] | select(. == \$r)))) | .name" "$SERVICES_FILE")
            if [ -z "$matching_services" ]; then
                WARNINGS+=("Service policy '$policy_name' references service roles that don't match any services: $service_roles")
            fi
        fi
        
        # Check if identity roles match any identities
        if [ -n "$identity_roles" ]; then
            local matching_identities=$(jq -r ".data[] | select(.roleAttributes // [] | any(. as \$r | (\"$identity_roles\" | split(\",\") | .[] | select(. == \$r)))) | .name" "$IDENTITIES_FILE")
            if [ -z "$matching_identities" ]; then
                WARNINGS+=("Service policy '$policy_name' references identity roles that don't match any identities: $identity_roles")
            fi
        fi
    done < <(jq -c '.data[]' "$SERVICE_POLICIES_FILE")
    
    echo ""
}

audit_terminators() {
    echo -e "${BLUE}=== Auditing Terminators ===${NC}"
    
    local terminator_count=$(jq -r '.data | length' "$TERMINATORS_FILE")
    echo -e "Total terminators: ${CYAN}${terminator_count}${NC}"
    
    if [ "$terminator_count" = "0" ]; then
        echo ""
        return
    fi
    
    while IFS= read -r terminator; do
        local terminator_id=$(echo "$terminator" | jq -r '.id')
        # Service and router can be either IDs (strings) or objects with .id field
        local service_id=$(echo "$terminator" | jq -r 'if .service | type == "string" then .service else .service.id // empty end')
        local router_id=$(echo "$terminator" | jq -r 'if .router | type == "string" then .router else .router.id // empty end')
        
        if [ -z "$service_id" ] || [ "$service_id" = "null" ]; then
            WARNINGS+=("Terminator '$terminator_id' has no service reference")
            continue
        fi
        
        if [ -z "$router_id" ] || [ "$router_id" = "null" ]; then
            WARNINGS+=("Terminator '$terminator_id' has no router reference")
            continue
        fi
        
        # Check if service exists
        local service_exists=$(jq -r ".data[] | select(.id == \"$service_id\") | .name" "$SERVICES_FILE")
        if [ -z "$service_exists" ]; then
            ISSUES+=("Terminator '$terminator_id' references non-existent service ID: $service_id")
        fi
        
        # Check if router exists (check both edge-routers and transit-routers)
        local router_exists=$(jq -r ".data[] | select(.id == \"$router_id\") | .name" "$EDGE_ROUTERS_FILE")
        if [ -z "$router_exists" ]; then
            # Also check transit routers (terminators can reference transit routers)
            local transit_router_exists=$(ziti edge list transit-routers --output-json 2>/dev/null | jq -r ".data[] | select(.id == \"$router_id\") | .name" || echo "")
            if [ -z "$transit_router_exists" ]; then
                WARNINGS+=("Terminator '$terminator_id' references router ID that may not exist: $router_id")
            fi
        fi
    done < <(jq -c '.data[]' "$TERMINATORS_FILE")
    
    echo ""
}

audit_basic_server_identities() {
    echo -e "${BLUE}=== Auditing Basic Server Identities ===${NC}"
    
    local basic_server_identities=$(jq -r '.data[] | select(.name | startswith("basic-server-")) | .name' "$IDENTITIES_FILE")
    
    if [ -n "$basic_server_identities" ]; then
        echo -e "${YELLOW}Found basic-server identities:${NC}"
        while IFS= read -r identity_name; do
            echo "  - $identity_name"
            
            # Get identity ID
            local identity_id=$(jq -r ".data[] | select(.name == \"$identity_name\") | .id" "$IDENTITIES_FILE")
            
            # Extract server info from identity name (basic-server-{name}-{role}-{env})
            local server_info=$(echo "$identity_name" | sed 's/^basic-server-//')
            
            # Check if there are any active sessions for this identity (by ID)
            local active_sessions=0
            if [ -f "$SESSIONS_FILE" ] && [ -s "$SESSIONS_FILE" ]; then
                active_sessions=$(jq -r ".data[]? | select(.identityId == \"$identity_id\") | .id" "$SESSIONS_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
            fi
            
            # Check if there are services associated with this identity
            # Pattern: ssh.{name}.{role}.{env}.ziti or https.{domain} for the server
            local server_pattern=$(echo "$server_info" | sed 's/-/./g')
            local related_services=$(jq -r ".data[] | select(.name | contains(\"$server_pattern\")) | .name" "$SERVICES_FILE" 2>/dev/null | wc -l | tr -d ' ')
            
            if [ "$active_sessions" = "0" ] && [ "$related_services" = "0" ]; then
                WARNINGS+=("Basic server identity '$identity_name' appears orphaned (no active sessions or related services)")
            fi
        done <<< "$basic_server_identities"
    else
        echo -e "${GREEN}No basic-server identities found${NC}"
    fi
    
    echo ""
}

audit_unused_policies() {
    echo -e "${BLUE}=== Auditing Unused Policies ===${NC}"
    
    # Check for service policies that don't match any services
    while IFS= read -r policy; do
        local policy_name=$(echo "$policy" | jq -r '.name')
        local service_roles=$(echo "$policy" | jq -r '.serviceRoles // [] | join(",")')
        
        if [ -n "$service_roles" ]; then
            # Remove # prefix for matching
            local roles_clean=$(echo "$service_roles" | sed 's/#//g' | tr ',' ' ')
            local has_match=false
            
            for role in $roles_clean; do
                local matching=$(jq -r ".data[] | select(.roleAttributes // [] | contains([\"$role\"])) | .name" "$SERVICES_FILE")
                if [ -n "$matching" ]; then
                    has_match=true
                    break
                fi
            done
            
            if [ "$has_match" = false ]; then
                WARNINGS+=("Service policy '$policy_name' may be unused (no matching services)")
            fi
        fi
    done < <(jq -c '.data[]' "$SERVICE_POLICIES_FILE")
    
    echo ""
}

audit_sessions() {
    echo -e "${BLUE}=== Auditing Sessions ===${NC}"
    
    local session_count=$(jq -r '.data | length' "$SESSIONS_FILE")
    echo -e "Total sessions: ${CYAN}${session_count}${NC}"
    
    if [ "$session_count" = "0" ]; then
        echo ""
        return
    fi
    
    # Check for sessions with invalid identity references
    while IFS= read -r session; do
        local session_id=$(echo "$session" | jq -r '.id')
        local identity_id=$(echo "$session" | jq -r '.identityId // empty')
        local service_id=$(echo "$session" | jq -r '.serviceId // empty')
        
        if [ -n "$identity_id" ] && [ "$identity_id" != "null" ]; then
            local identity_exists=$(jq -r ".data[] | select(.id == \"$identity_id\") | .name" "$IDENTITIES_FILE")
            if [ -z "$identity_exists" ]; then
                ISSUES+=("Session '$session_id' references non-existent identity ID: $identity_id")
            fi
        fi
        
        if [ -n "$service_id" ] && [ "$service_id" != "null" ]; then
            local service_exists=$(jq -r ".data[] | select(.id == \"$service_id\") | .name" "$SERVICES_FILE")
            if [ -z "$service_exists" ]; then
                ISSUES+=("Session '$session_id' references non-existent service ID: $service_id")
            fi
        fi
    done < <(jq -c '.data[]' "$SESSIONS_FILE")
    
    echo ""
}

# =============================================================================
# Summary Report
# =============================================================================

print_summary() {
    echo -e "${BLUE}=== Audit Summary ===${NC}"
    echo ""
    
    # Resource counts
    local identity_count=$(jq -r '.data | length' "$IDENTITIES_FILE")
    local service_count=$(jq -r '.data | length' "$SERVICES_FILE")
    local config_count=$(jq -r '.data | length' "$CONFIGS_FILE")
    local policy_count=$(jq -r '.data | length' "$SERVICE_POLICIES_FILE")
    local terminator_count=$(jq -r '.data | length' "$TERMINATORS_FILE")
    local session_count=$(jq -r '.data | length' "$SESSIONS_FILE")
    
    echo -e "${CYAN}Resource Counts:${NC}"
    echo "  Identities: $identity_count"
    echo "  Services: $service_count"
    echo "  Configs: $config_count"
    echo "  Service Policies: $policy_count"
    echo "  Terminators: $terminator_count"
    echo "  Sessions: $session_count"
    echo ""
    
    # Issues
    if [ ${#ISSUES[@]} -gt 0 ]; then
        echo -e "${RED}Issues Found (${#ISSUES[@]}):${NC}"
        for issue in "${ISSUES[@]}"; do
            echo -e "  ${RED}✗${NC} $issue"
        done
        echo ""
    else
        echo -e "${GREEN}✓ No critical issues found${NC}"
        echo ""
    fi
    
    # Warnings
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Warnings (${#WARNINGS[@]}):${NC}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $warning"
        done
        echo ""
    else
        echo -e "${GREEN}✓ No warnings${NC}"
        echo ""
    fi
    
    # Recommendations
    echo -e "${CYAN}Recommendations:${NC}"
    echo "  1. Review orphaned basic-server identities and clean up if servers are destroyed"
    echo "  2. Remove unused configs that aren't referenced by any services"
    echo "  3. Review and update policies that don't match any resources"
    echo "  4. Clean up terminators for non-existent services"
    echo "  5. Run this audit regularly (e.g., monthly) to catch issues early"
    echo ""
    
    if [ ${#ISSUES[@]} -gt 0 ] || [ ${#WARNINGS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Consider running cleanup scripts or manual cleanup for the issues above.${NC}"
    else
        echo -e "${GREEN}✓ Ziti resources appear healthy${NC}"
    fi
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    check_ziti_cli
    login_ziti
    fetch_resources
    
    audit_orphaned_services
    audit_orphaned_configs
    audit_service_policies
    audit_terminators
    audit_basic_server_identities
    audit_unused_policies
    audit_sessions
    
    print_summary
}

main

