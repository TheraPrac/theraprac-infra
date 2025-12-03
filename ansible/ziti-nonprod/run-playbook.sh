#!/bin/bash
# =============================================================================
# Ziti Ansible Playbook Runner
# =============================================================================
# Connects via Ziti overlay network (requires ZDE running).
# Falls back to EICE if Ziti is unavailable.
#
# SSH is configured with persistent keys (ansible@theraprac.com)
# No ephemeral key pushing needed.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZITI_HOST="ssh.ziti-nonprod.ziti"
TF_DIR="$SCRIPT_DIR/../../infra/phase4-ziti"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd "$SCRIPT_DIR"

# Cross-platform connectivity check (works with both GNU and BSD netcat)
check_ziti_connectivity() {
    # Use timeout command which is available on both macOS and Linux
    # Falls back to a simple connection test if timeout isn't available
    if command -v timeout &>/dev/null; then
        timeout 2 bash -c "echo >/dev/tcp/$ZITI_HOST/22" 2>/dev/null
    elif command -v gtimeout &>/dev/null; then
        # macOS with coreutils installed
        gtimeout 2 bash -c "echo >/dev/tcp/$ZITI_HOST/22" 2>/dev/null
    else
        # Fallback: use bash /dev/tcp with background job
        (echo >/dev/tcp/$ZITI_HOST/22) &
        local pid=$!
        sleep 2
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            return 1
        fi
        wait $pid 2>/dev/null
    fi
}

# Check if Ziti tunnel is working
echo -e "${GREEN}Checking Ziti connectivity...${NC}"
if check_ziti_connectivity; then
    echo -e "${GREEN}✓ Ziti tunnel active - using Ziti inventory${NC}"
    INVENTORY="inventory/ziti.yml"
else
    echo -e "${YELLOW}⚠ Ziti tunnel not available - falling back to EICE${NC}"
    INVENTORY="inventory/eice.yml"
    
    # EICE requires AWS credentials
    if [ -z "$AWS_PROFILE" ]; then
        export AWS_PROFILE="jfinlinson_admin"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${YELLOW}AWS session expired. Running 'aws sso login'...${NC}"
        aws sso login --profile "$AWS_PROFILE"
    fi
    
    # Get instance ID from Terraform (required for EICE inventory)
    if [ -z "$ZITI_INSTANCE_ID" ]; then
        echo -e "${GREEN}Getting instance ID from Terraform...${NC}"
        export ZITI_INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw ziti_ec2_id 2>/dev/null)
        if [ -z "$ZITI_INSTANCE_ID" ]; then
            echo -e "${RED}Error: Could not get instance ID from Terraform.${NC}"
            echo -e "${RED}Run 'terraform -chdir=$TF_DIR output' to check state.${NC}"
            exit 1
        fi
        echo -e "${GREEN}Instance ID: $ZITI_INSTANCE_ID${NC}"
    fi
fi

echo -e "${GREEN}Running Ansible playbook with ${INVENTORY}...${NC}"
ansible-playbook -i "$INVENTORY" playbook.yml "$@"
