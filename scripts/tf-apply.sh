#!/bin/bash
# =============================================================================
# TheraPrac Terraform Apply Wrapper
# =============================================================================
# Applies a terraform plan file.
#
# Usage:
#   scripts/tf-apply.sh [phase]
#
# Examples:
#   scripts/tf-apply.sh phase4-ziti
#   scripts/tf-apply.sh phase1-vpc
#
# Or from within a phase directory:
#   cd infra/phase4-ziti
#   ../../scripts/tf-apply.sh
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
    echo "Usage: scripts/tf-apply.sh [phase-name]"
    echo "  e.g., scripts/tf-apply.sh phase4-ziti"
    exit 1
fi

PLAN_FILE="tfplan"

# Check if plan file exists
if [ ! -f "$PLAN_FILE" ]; then
    echo -e "${RED}ERROR: No plan file found at $(pwd)/$PLAN_FILE${NC}"
    echo ""
    echo "Run terraform plan first:"
    echo "    terraform plan -out=$PLAN_FILE"
    echo ""
    echo "Or use the wrapper:"
    echo "    scripts/tf-plan.sh $(basename $(pwd))"
    exit 1
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Terraform Apply: $(basename $(pwd))${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Show what we're about to apply
echo -e "${YELLOW}Plan summary:${NC}"
terraform show -no-color "$PLAN_FILE" | grep -E "^(Plan:|No changes\.)" || true
echo ""

# Confirm before applying
read -p "Apply this plan? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}Running: terraform apply $PLAN_FILE${NC}"
    echo ""
    
    if terraform apply "$PLAN_FILE"; then
        echo ""
        echo -e "${GREEN}Apply completed successfully!${NC}"
        
        # Clean up plan file after successful apply
        rm -f "$PLAN_FILE"
        echo -e "${YELLOW}Cleaned up plan file.${NC}"
    else
        echo ""
        echo -e "${RED}Terraform apply failed!${NC}"
        exit 1
    fi
else
    echo ""
    echo -e "${YELLOW}Apply cancelled.${NC}"
    exit 0
fi







