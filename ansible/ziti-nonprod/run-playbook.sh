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

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd "$SCRIPT_DIR"

# Check if Ziti tunnel is working
echo -e "${GREEN}Checking Ziti connectivity...${NC}"
if nc -z -w 2 "$ZITI_HOST" 22 2>/dev/null; then
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
fi

echo -e "${GREEN}Running Ansible playbook with ${INVENTORY}...${NC}"
ansible-playbook -i "$INVENTORY" playbook.yml "$@"
