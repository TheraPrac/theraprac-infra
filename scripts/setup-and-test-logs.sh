#!/bin/bash
# =============================================================================
# Complete Setup and Test for CloudWatch Logs
# =============================================================================
# This script:
# 1. Validates Terraform configuration
# 2. Plans Terraform changes (shows what will be created)
# 3. Validates Ansible configuration
# 4. Runs test script to verify setup
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra/phase3-iam"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CloudWatch Logs Setup & Test${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# =============================================================================
# Step 1: Validate Terraform
# =============================================================================

echo -e "${YELLOW}[1/4] Validating Terraform configuration...${NC}"

cd "$INFRA_DIR"

if terraform validate > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Terraform configuration is valid"
else
    echo -e "  ${RED}✗${NC} Terraform validation failed"
    terraform validate
    exit 1
fi

# =============================================================================
# Step 2: Terraform Plan (Dry Run)
# =============================================================================

echo ""
echo -e "${YELLOW}[2/4] Running Terraform plan (dry run)...${NC}"

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo "  Initializing Terraform..."
    terraform init -backend=false > /dev/null 2>&1 || {
        echo -e "  ${YELLOW}⚠${NC} Could not initialize Terraform (needs AWS credentials)"
        echo "  Skipping plan step"
    }
fi

if terraform plan -out=/tmp/tfplan \
    -var="environment=${ENVIRONMENT}" \
    -var="aws_region=us-west-2" \
    > /tmp/tfplan-output.txt 2>&1; then
    
    echo -e "  ${GREEN}✓${NC} Terraform plan completed"
    
    # Show CloudWatch log group changes
    if grep -q "aws_cloudwatch_log_group" /tmp/tfplan-output.txt; then
        echo ""
        echo -e "  ${BLUE}CloudWatch Log Groups to be created/updated:${NC}"
        grep -A 5 "aws_cloudwatch_log_group" /tmp/tfplan-output.txt | head -20
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Terraform plan failed (may need AWS credentials)"
    echo "  This is expected if you haven't configured AWS credentials"
fi

# =============================================================================
# Step 3: Validate Ansible
# =============================================================================

echo ""
echo -e "${YELLOW}[3/4] Validating Ansible configuration...${NC}"

ANSIBLE_DIR="$SCRIPT_DIR/../ansible/basic-server"
cd "$ANSIBLE_DIR"

if ansible-playbook --syntax-check deploy-api.yml > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Ansible playbook syntax is valid"
else
    # Try with a dummy inventory
    if ansible-playbook --syntax-check deploy-api.yml \
        -i localhost, \
        -e "target_env=${ENVIRONMENT}" \
        > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Ansible playbook syntax is valid"
    else
        echo -e "  ${YELLOW}⚠${NC} Could not fully validate Ansible (needs inventory)"
    fi
fi

# =============================================================================
# Step 4: Run Test Script
# =============================================================================

echo ""
echo -e "${YELLOW}[4/4] Running CloudWatch logs test...${NC}"
echo ""

cd "$SCRIPT_DIR"

if [ -f "test-cloudwatch-logs.sh" ]; then
    if ./test-cloudwatch-logs.sh "$ENVIRONMENT" 2>&1; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}All tests passed!${NC}"
        echo -e "${GREEN}========================================${NC}"
    else
        echo ""
        echo -e "${YELLOW}Some tests had warnings or failures${NC}"
        echo "This may be expected if:"
        echo "  - Log groups haven't been created yet (run: terraform apply)"
        echo "  - SSM parameters not set (will be set on deployment)"
        echo "  - Not running on EC2 instance"
    fi
else
    echo -e "  ${RED}✗${NC} Test script not found"
    exit 1
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Apply Terraform to create log groups:"
echo "   cd $INFRA_DIR"
echo "   terraform plan -var='environment=${ENVIRONMENT}'"
echo "   terraform apply -var='environment=${ENVIRONMENT}'"
echo ""
echo "2. Deploy application:"
echo "   cd $ANSIBLE_DIR"
echo "   ansible-playbook deploy-api.yml -i inventory/${ENVIRONMENT} -e 'target_env=${ENVIRONMENT} version=latest'"
echo ""
echo "3. Verify logs after deployment:"
echo "   $SCRIPT_DIR/verify-deployment-logs.sh ${ENVIRONMENT}"



