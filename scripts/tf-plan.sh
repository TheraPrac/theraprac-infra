#!/bin/bash
# =============================================================================
# TheraPrac Terraform Plan Wrapper
# =============================================================================
# Runs terraform plan with proper output file handling.
#
# Usage:
#   scripts/tf-plan.sh [phase]
#
# Examples:
#   scripts/tf-plan.sh phase4-ziti
#   scripts/tf-plan.sh phase1-vpc
#
# Or from within a phase directory:
#   cd infra/phase4-ziti
#   ../../scripts/tf-plan.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Determine working directory
if [ -n "$1" ]; then
    PHASE_DIR="infra/$1"
    if [ ! -d "$PHASE_DIR" ]; then
        echo -e "${RED}ERROR: Directory $PHASE_DIR does not exist${NC}"
        exit 1
    fi
    cd "$PHASE_DIR"
    echo -e "${YELLOW}Changed to: $(pwd)${NC}"
fi

# Check we're in a terraform directory
if [ ! -f "main.tf" ]; then
    echo -e "${RED}ERROR: No main.tf found in current directory${NC}"
    echo "Usage: scripts/tf-plan.sh [phase-name]"
    echo "  e.g., scripts/tf-plan.sh phase4-ziti"
    exit 1
fi

PLAN_FILE="tfplan"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Terraform Plan: $(basename $(pwd))${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Clean up any existing plan file
rm -f "$PLAN_FILE"

# Run terraform plan with output file
echo -e "${YELLOW}Running: terraform plan -out=$PLAN_FILE -no-color${NC}"
echo ""

if terraform plan -out="$PLAN_FILE" -no-color; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Plan Summary${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Show plan summary (without the long footer)
    terraform show -no-color "$PLAN_FILE" | grep -E "^(Plan:|No changes\.)" || true
    
    echo ""
    echo -e "${GREEN}Plan saved to: $(pwd)/$PLAN_FILE${NC}"
    echo ""
    echo -e "${YELLOW}To apply this plan, run:${NC}"
    echo ""
    echo "    terraform apply $PLAN_FILE"
    echo ""
else
    echo ""
    echo -e "${RED}Terraform plan failed!${NC}"
    exit 1
fi







