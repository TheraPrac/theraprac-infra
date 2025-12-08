#!/bin/bash
# =============================================================================
# Create Ziti Database Service
# =============================================================================
# This script creates the Ziti service for PostgreSQL database access.
# Run this after deploying the RDS instance with Terraform.
#
# Prerequisites:
#   - AWS credentials configured (source scripts/aws-auth.sh)
#   - RDS instance deployed (phase5-rds)
#   - Edge router identity exists
#
# Usage:
#   ./scripts/create-db-service.sh [environment]
#   ./scripts/create-db-service.sh dev    # default
#   ./scripts/create-db-service.sh test
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default environment
ENVIRONMENT="${1:-dev}"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Create Ziti Database Service${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "Environment: ${GREEN}${ENVIRONMENT}${NC}"
echo ""

# Change to phase5-rds directory
cd "$REPO_ROOT/infra/phase5-rds"

# Check if Terraform state exists
if ! terraform state list >/dev/null 2>&1; then
    echo -e "${RED}Error: Terraform state not found for phase5-rds${NC}"
    echo -e "${YELLOW}Please deploy RDS first:${NC}"
    echo "  cd infra/phase5-rds"
    echo "  terraform init"
    echo "  terraform plan -var=\"environment=${ENVIRONMENT}\" -out=tfplan"
    echo "  terraform apply tfplan"
    exit 1
fi

# Get RDS endpoint from Terraform
echo -e "${BLUE}Getting RDS endpoint from Terraform...${NC}"
RDS_ENDPOINT=$(terraform output -raw db_address 2>/dev/null)

if [ -z "$RDS_ENDPOINT" ]; then
    echo -e "${RED}Error: Could not get RDS endpoint from Terraform${NC}"
    echo -e "${YELLOW}Make sure RDS is deployed and terraform output db_address works${NC}"
    exit 1
fi

echo -e "RDS Endpoint: ${GREEN}${RDS_ENDPOINT}${NC}"
echo ""

# Change to ansible directory
cd "$REPO_ROOT/ansible/ziti-nonprod"

# Run Ansible playbook
echo -e "${BLUE}Creating Ziti database service...${NC}"
echo ""

ansible-playbook -i inventory/ziti.yml create-db-service.yml \
    -e "rds_endpoint=${RDS_ENDPOINT}" \
    -e "db_environment=${ENVIRONMENT}"

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Database service created successfully!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "Service Name: ${BLUE}postgres.db.${ENVIRONMENT}.app.ziti${NC}"
echo -e "Port:         ${BLUE}5432${NC}"
echo ""
echo -e "${YELLOW}To connect from authorized identity:${NC}"
echo -e "  psql -h postgres.db.${ENVIRONMENT}.app.ziti -U theraprac -d theraprac"
echo ""

