#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Basic Server Provisioning Script
# =============================================================================
# Creates a private EC2 instance with self-hosted Ziti tunneler for SSH access.
#
# This script:
#   1. Destroys any existing infrastructure (clean slate)
#   2. Creates EC2 instance with Ziti binaries installed
#   3. Runs Ansible ON the server (via EICE) to:
#      - Create Ziti identity
#      - Enroll identity
#      - Register SSH service
#      - Start ziti-edge-tunnel
#
# Usage:
#   ./scripts/provision-basic-server.sh              # Interactive mode
#   ./scripts/provision-basic-server.sh --non-interactive  # Auto-accept all prompts
#   ./scripts/provision-basic-server.sh -y            # Short form (auto-accept)
#
# The script will prompt for:
#   - Name: Server purpose (app, api, web, database, cache, queue, worker, scheduler)
#   - Role: Identifier (api, web, db, cache, queue, worker, scheduler, mt)
#   - Tier: Determines subnet placement (app, db, ziti)
#   - Environment: prod, nonprod, dev, test, stage, uat
#   - Instance type: t4g.micro, t4g.small, etc.
#   - Architecture: arm64 or x86_64
# =============================================================================

set -e

# Check for non-interactive mode
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
if [[ "$1" == "--non-interactive" ]] || [[ "$1" == "-y" ]]; then
    NON_INTERACTIVE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/phase7-basic-server"
ZITI_TF_DIR="$REPO_ROOT/infra/phase4-ziti"
ANSIBLE_DIR="$REPO_ROOT/ansible/basic-server"
CACHE_FILE="$REPO_ROOT/.provision-basic-server-cache"

# =============================================================================
# Helper Functions
# =============================================================================

prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local value

    if [ "$NON_INTERACTIVE" = "true" ]; then
        # Non-interactive mode: use default or fail if no default
        if [ -n "$default_value" ]; then
            value="$default_value"
            echo -e "${BLUE}$prompt_text [$default_value]: ${value}${NC}"
        else
            echo -e "${RED}Error: Non-interactive mode requires a default value for: $prompt_text${NC}"
            exit 1
        fi
    else
        if [ -n "$default_value" ]; then
            read -p "$prompt_text [$default_value]: " value
            value="${value:-$default_value}"
        else
            while [ -z "$value" ]; do
                read -p "$prompt_text: " value
                if [ -z "$value" ]; then
                    echo -e "${RED}This field is required.${NC}"
                fi
            done
        fi
    fi

    eval "$var_name=\"$value\""
}

prompt_choice() {
    local var_name="$1"
    local prompt_text="$2"
    local options="$3"
    local default_value="$4"
    local value
    local valid=false

    echo -e "${BLUE}$prompt_text${NC}"
    echo "  Options: $options"
    
    if [ "$NON_INTERACTIVE" = "true" ]; then
        # Non-interactive mode: use default or fail if no default
        if [ -n "$default_value" ]; then
            value="$default_value"
            echo -e "${BLUE}  Choice [$default_value]: ${value}${NC}"
        else
            echo -e "${RED}Error: Non-interactive mode requires a default value for: $prompt_text${NC}"
            exit 1
        fi
    else
        while [ "$valid" = "false" ]; do
            if [ -n "$default_value" ]; then
                read -p "  Choice [$default_value]: " value
                value="${value:-$default_value}"
            else
                read -p "  Choice: " value
            fi
            
            # Validate choice is in options list
            if [ -n "$value" ]; then
                # Convert options string to array and check if value is in it
                # Replace commas with spaces, then split into array
                local options_normalized=$(echo "$options" | tr ',' ' ')
                local found=false
                for option in $options_normalized; do
                    # Trim whitespace from option
                    option=$(echo "$option" | xargs)
                    if [ "$option" = "$value" ]; then
                        found=true
                        break
                    fi
                done
                
                if [ "$found" = "true" ]; then
                    valid=true
                else
                    echo -e "${RED}Invalid choice '$value'. Please select from: $options${NC}"
                fi
            else
                echo -e "${RED}This field is required.${NC}"
            fi
        done
    fi

    eval "$var_name=\"$value\""
}

# =============================================================================
# AWS Credentials Management
# =============================================================================

ensure_aws_credentials() {
    local profile="${AWS_PROFILE:-jfinlinson_admin}"
    local max_retries=3
    local retry=0
    
    # Check if credentials are valid
    if aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ AWS credentials valid${NC}"
        export AWS_PROFILE="$profile"
        # Export credentials for Terraform
        eval $(aws configure export-credentials --profile "$profile" --format env 2>/dev/null) || {
            echo -e "${YELLOW}Warning: Could not export credentials. Terraform may need AWS_PROFILE set.${NC}"
        }
        return 0
    fi
    
    # Credentials expired or not configured - attempt SSO login
    echo -e "${YELLOW}AWS session expired or not configured.${NC}"
    
    while [ $retry -lt $max_retries ]; do
        echo -e "${BLUE}Attempting SSO login (attempt $((retry + 1))/$max_retries)...${NC}"
        
        if aws sso login --profile "$profile" 2>&1; then
            # Wait for SSO session to initialize (SSO token file creation can be delayed)
            echo -e "${BLUE}Waiting for SSO session to initialize...${NC}"
            local wait_count=0
            while [ $wait_count -lt 10 ]; do
                sleep 1
                if aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
                    break
                fi
                wait_count=$((wait_count + 1))
            done
            
            # Verify login worked
            if aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ SSO login successful${NC}"
                export AWS_PROFILE="$profile"
                
                # Export credentials for Terraform (which doesn't handle SSO well)
                echo -e "${BLUE}Exporting credentials for Terraform...${NC}"
                eval $(aws configure export-credentials --profile "$profile" --format env 2>/dev/null) || {
                    echo -e "${YELLOW}Warning: Could not export credentials. Terraform may need AWS_PROFILE set.${NC}"
                }
                return 0
            else
                echo -e "${YELLOW}SSO login completed but credentials not yet available. Retrying...${NC}"
                retry=$((retry + 1))
                sleep 2
            fi
        else
            echo -e "${YELLOW}SSO login attempt failed. Retrying...${NC}"
            retry=$((retry + 1))
            sleep 2
        fi
    done
    
    echo -e "${RED}SSO login failed after $max_retries attempts. Please run manually:${NC}"
    echo "  aws sso login --profile $profile"
    return 1
}

# =============================================================================
# Cache Management
# =============================================================================

load_cache() {
    if [ -f "$CACHE_FILE" ]; then
        source "$CACHE_FILE"
        return 0
    fi
    return 1
}

save_cache() {
    cat > "$CACHE_FILE" <<EOF
# Cached values from last provisioning run
# Generated: $(date)
CACHED_NAME="$NAME"
CACHED_ROLE="$ROLE"
CACHED_TIER="$TIER"
CACHED_ENV="$ENV"
CACHED_INSTANCE_TYPE="$INSTANCE_TYPE"
CACHED_ARCH="$ARCH"
EOF
    # Add to .gitignore if not already there
    if [ -f "$REPO_ROOT/.gitignore" ] && ! grep -q "^\.provision-basic-server-cache$" "$REPO_ROOT/.gitignore"; then
        echo ".provision-basic-server-cache" >> "$REPO_ROOT/.gitignore"
    fi
}

# =============================================================================
# Load SSH Keys from phase4-ziti terraform.tfvars
# =============================================================================

load_ssh_keys() {
    local tfvars_file="$ZITI_TF_DIR/terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        echo -e "${RED}Error: SSH keys file not found: $tfvars_file${NC}"
        echo "Please ensure phase4-ziti has been configured with terraform.tfvars"
        exit 1
    fi

    # Extract SSH keys from tfvars
    SSH_KEY_ANSIBLE=$(grep '^ssh_key_ansible' "$tfvars_file" | sed 's/.*= *"\(.*\)"/\1/')
    SSH_KEY_JFINLINSON=$(grep '^ssh_key_jfinlinson' "$tfvars_file" | sed 's/.*= *"\(.*\)"/\1/')

    if [ -z "$SSH_KEY_ANSIBLE" ] || [ -z "$SSH_KEY_JFINLINSON" ]; then
        echo -e "${RED}Error: Could not load SSH keys from $tfvars_file${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Loaded SSH keys from phase4-ziti${NC}"
}

# =============================================================================
# Main Script
# =============================================================================

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       TheraPrac Basic Server Provisioning                    ║${NC}"
echo -e "${BLUE}║       (Tunneler Model - Self-Hosted Ziti)                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ensure AWS credentials are valid (auto-login if needed)
if ! ensure_aws_credentials; then
    exit 1
fi

# Load SSH keys
load_ssh_keys

echo ""
echo -e "${BLUE}=== Server Configuration ===${NC}"
echo ""

# Try to load cached values
if load_cache && [ -n "$CACHED_NAME" ]; then
    echo -e "${GREEN}Found cached values from last run:${NC}"
    echo "  Name: $CACHED_NAME, Role: $CACHED_ROLE, Tier: $CACHED_TIER"
    echo "  Environment: $CACHED_ENV, Type: $CACHED_INSTANCE_TYPE, Arch: $CACHED_ARCH"
    echo ""
    if [ "$NON_INTERACTIVE" = "true" ]; then
        REPLY="Y"
        echo -e "${BLUE}Use cached values? [Y/n]: Y (non-interactive)${NC}"
    else
        read -p "Use cached values? [Y/n] " -n 1 -r
        echo
    fi
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        NAME="$CACHED_NAME"
        ROLE="$CACHED_ROLE"
        TIER="$CACHED_TIER"
        ENV="$CACHED_ENV"
        INSTANCE_TYPE="$CACHED_INSTANCE_TYPE"
        ARCH="$CACHED_ARCH"
        echo -e "${GREEN}Using cached values${NC}"
    else
        # User wants to enter new values - clear cache and prompt
        rm -f "$CACHE_FILE"
        prompt_choice NAME "Name (server purpose)" "app, api, web, database, cache, queue, worker, scheduler" "app"
        prompt_choice ROLE "Role (identifier)" "api, web, db, cache, queue, worker, scheduler, mt" "api"
        prompt_choice TIER "Tier (determines subnet: app, db, or ziti)" "app, db, ziti" "app"
        prompt_choice ENV "Environment" "prod, nonprod, dev, test, stage, uat" "nonprod"
        prompt INSTANCE_TYPE "Instance type" "t4g.micro"
        prompt_choice ARCH "Architecture" "arm64, x86_64" "arm64"
    fi
else
    # No cache - prompt for all values
    prompt_choice NAME "Name (server purpose)" "app, api, web, database, cache, queue, worker, scheduler" "app"
    prompt_choice ROLE "Role (identifier)" "api, web, db, cache, queue, worker, scheduler, mt" "api"
    prompt_choice TIER "Tier (determines subnet: app, db, or ziti)" "app, db, ziti" "app"
    prompt_choice ENV "Environment" "prod, nonprod, dev, test, stage, uat" "nonprod"
    prompt INSTANCE_TYPE "Instance type" "t4g.micro"
    prompt_choice ARCH "Architecture" "arm64, x86_64" "arm64"
fi

# Derive names
FULL_NAME="${NAME}.${ROLE}.${ENV}"
HYPHEN_NAME="${NAME}-${ROLE}-${ENV}"
SUBNET="private-${TIER}-${ENV}-az1"
INTERNAL_DNS="${HYPHEN_NAME}.theraprac-internal.com"
ZITI_SSH="ssh.${FULL_NAME}.ziti"
ZITI_IDENTITY_NAME="${FULL_NAME}"

echo ""
echo -e "${BLUE}=== Configuration Summary ===${NC}"
echo ""
echo -e "  Full Name:     ${GREEN}${FULL_NAME}${NC}"
echo -e "  Subnet:        ${SUBNET} (tier: ${TIER})"
echo -e "  Instance Type: ${INSTANCE_TYPE}"
echo -e "  Architecture:  ${ARCH}"
echo ""
echo -e "  Internal DNS:  ${GREEN}${INTERNAL_DNS}${NC}"
echo -e "  Ziti SSH:      ${GREEN}${ZITI_SSH}${NC}"
echo -e "  Ziti Identity: ${GREEN}${ZITI_IDENTITY_NAME}${NC}"
echo ""

if [ "$NON_INTERACTIVE" = "true" ]; then
    REPLY="y"
    echo -e "${BLUE}Continue? [y/N]: y (non-interactive)${NC}"
else
    read -p "Continue? [y/N] " -n 1 -r
    echo
fi
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Save values to cache for next time
save_cache

# =============================================================================
# Terraform - Destroy Existing Resources
# =============================================================================

echo ""
echo -e "${BLUE}=== Checking for Existing Infrastructure ===${NC}"
echo ""

# Re-export credentials for Terraform (ensures fresh credentials)
echo -e "${BLUE}Refreshing AWS credentials for Terraform...${NC}"
eval $(aws configure export-credentials --profile "${AWS_PROFILE:-jfinlinson_admin}" --format env 2>/dev/null) || {
    echo -e "${YELLOW}Warning: Could not export credentials. Attempting to refresh...${NC}"
    # Try to ensure credentials are still valid
    if ! ensure_aws_credentials; then
        echo -e "${RED}Failed to refresh AWS credentials. Exiting.${NC}"
        exit 1
    fi
    # Re-export after refresh
    eval $(aws configure export-credentials --profile "${AWS_PROFILE:-jfinlinson_admin}" --format env 2>/dev/null) || {
        echo -e "${RED}Failed to export credentials for Terraform.${NC}"
        exit 1
    }
}

cd "$TF_DIR"

# Initialize Terraform (always use -reconfigure to ensure backend is properly configured)
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init -reconfigure

# Check if resources exist
set +e
terraform state list 2>/dev/null | grep -q "module.basic_server"
RESOURCES_EXIST=$?
set -e

if [ $RESOURCES_EXIST -eq 0 ]; then
    echo -e "${YELLOW}⚠ Existing infrastructure detected${NC}"
    echo ""
    
    if [ "$NON_INTERACTIVE" = "true" ]; then
        REPLY="y"
        echo -e "${BLUE}Destroy existing resources before creating new ones? [y/N]: y (non-interactive)${NC}"
    else
        read -p "Destroy existing resources before creating new ones? [y/N] " -n 1 -r
        echo
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Destroying existing infrastructure...${NC}"
        if ! terraform destroy \
            -var="name=$NAME" \
            -var="role=$ROLE" \
            -var="tier=$TIER" \
            -var="environment=$ENV" \
            -var="instance_type=$INSTANCE_TYPE" \
            -var="arch=$ARCH" \
            -var="ssh_key_ansible=$SSH_KEY_ANSIBLE" \
            -var="ssh_key_jfinlinson=$SSH_KEY_JFINLINSON" \
            -auto-approve 2>&1 | tee /tmp/terraform-destroy.log; then
            
            # Check if error was due to state lock
            if grep -q "Error acquiring the state lock" /tmp/terraform-destroy.log; then
                LOCK_ID=$(grep -oP 'ID:\s+\K[^\s]+' /tmp/terraform-destroy.log | head -1)
                if [ -n "$LOCK_ID" ]; then
                    echo -e "${YELLOW}State lock detected. Attempting to unlock...${NC}"
                    if terraform force-unlock -force "$LOCK_ID" 2>/dev/null; then
                        echo -e "${GREEN}✓ Lock released. Retrying destroy...${NC}"
                        terraform destroy \
                            -var="name=$NAME" \
                            -var="role=$ROLE" \
                            -var="tier=$TIER" \
                            -var="environment=$ENV" \
                            -var="instance_type=$INSTANCE_TYPE" \
                            -var="arch=$ARCH" \
                            -var="ssh_key_ansible=$SSH_KEY_ANSIBLE" \
                            -var="ssh_key_jfinlinson=$SSH_KEY_JFINLINSON" \
                            -auto-approve
                    else
                        echo -e "${RED}Failed to unlock. Please unlock manually:${NC}"
                        echo "  terraform force-unlock -force $LOCK_ID"
                        exit 1
                    fi
                fi
            else
                echo -e "${RED}Destroy failed. Check /tmp/terraform-destroy.log for details.${NC}"
                exit 1
            fi
        fi
        echo -e "${GREEN}✓ Existing infrastructure destroyed${NC}"
    else
        echo -e "${YELLOW}Skipping destroy - will attempt to update in place${NC}"
    fi
else
    echo -e "${GREEN}✓ No existing infrastructure found${NC}"
fi

# =============================================================================
# Terraform - Create New Resources
# =============================================================================

echo ""
echo -e "${BLUE}=== Creating Infrastructure ===${NC}"
echo ""

# Re-export credentials again (they might have expired during destroy)
eval $(aws configure export-credentials --profile "${AWS_PROFILE:-jfinlinson_admin}" --format env 2>/dev/null) || {
    echo -e "${RED}Failed to refresh credentials. Exiting.${NC}"
    exit 1
}

# Plan
echo -e "${YELLOW}Planning...${NC}"
terraform plan \
    -var="name=$NAME" \
    -var="role=$ROLE" \
    -var="tier=$TIER" \
    -var="environment=$ENV" \
    -var="instance_type=$INSTANCE_TYPE" \
    -var="arch=$ARCH" \
    -var="ssh_key_ansible=$SSH_KEY_ANSIBLE" \
    -var="ssh_key_jfinlinson=$SSH_KEY_JFINLINSON" \
    -out=tfplan

echo ""
if [ "$NON_INTERACTIVE" = "true" ]; then
    REPLY="y"
    echo -e "${BLUE}Apply this plan? [y/N]: y (non-interactive)${NC}"
else
    read -p "Apply this plan? [y/N] " -n 1 -r
    echo
fi
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Re-export credentials again before apply (they might have expired during plan)
echo -e "${BLUE}Refreshing credentials before apply...${NC}"
eval $(aws configure export-credentials --profile "${AWS_PROFILE:-jfinlinson_admin}" --format env 2>/dev/null) || {
    echo -e "${RED}Failed to refresh credentials. Exiting.${NC}"
    exit 1
}

# Apply
echo -e "${YELLOW}Applying...${NC}"
terraform apply tfplan

# Capture outputs
INSTANCE_ID=$(terraform output -raw instance_id)
SERVER_INTERNAL_DNS=$(terraform output -raw internal_dns)
SERVER_ZITI_SSH=$(terraform output -raw ziti_ssh)
ZITI_CONTROLLER_ENDPOINT=$(terraform output -raw ziti_controller_endpoint)
ZITI_IDENTITY=$(terraform output -raw ziti_identity_name)

echo ""
echo -e "${GREEN}✓ Terraform complete${NC}"
echo "  Instance ID: $INSTANCE_ID"

# =============================================================================
# Wait for Instance to be Ready
# =============================================================================

echo ""
echo -e "${BLUE}=== Waiting for Instance to be Ready ===${NC}"
echo ""

echo -e "${YELLOW}Waiting for instance to pass status checks...${NC}"
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --region us-west-2

echo -e "${YELLOW}Waiting for user-data script to complete (user setup)...${NC}"
# Give the user-data script time to complete (just user creation, no Ziti installation)
sleep 15

echo -e "${GREEN}✓ Instance ready (Ansible will install Ziti)${NC}"

# =============================================================================
# Ansible - Configure Ziti on Server
# =============================================================================

echo ""
echo -e "${BLUE}=== Configuring Ziti on Server ===${NC}"
echo ""

cd "$ANSIBLE_DIR"

# Always use EICE for Ansible on the server
# (Ziti is not yet configured, so we can't use Ziti tunnel)
echo -e "${YELLOW}Connecting to server via EICE...${NC}"
ANSIBLE_INVENTORY="$ANSIBLE_DIR/inventory/server-eice.yml"

# Run Ansible playbook on the server
ansible-playbook playbook.yml \
    -i "$ANSIBLE_INVENTORY" \
    -e "server_name=$FULL_NAME" \
    -e "ziti_ssh_name=$SERVER_ZITI_SSH" \
    -e "ziti_identity_name=$ZITI_IDENTITY" \
    -e "ziti_controller_endpoint=$ZITI_CONTROLLER_ENDPOINT"

# =============================================================================
# Done
# =============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Provisioning Complete!                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Server:        ${FULL_NAME}"
echo -e "  Instance ID:   ${INSTANCE_ID}"
echo -e "  Internal DNS:  ${SERVER_INTERNAL_DNS}"
echo -e "  Ziti Identity: ${ZITI_IDENTITY}"
echo ""
echo -e "  ${BLUE}SSH via Ziti (requires ZDE running):${NC}"
echo -e "    ssh jfinlinson@${SERVER_ZITI_SSH}"
echo ""
echo -e "  ${YELLOW}SSH via EICE (break-glass):${NC}"
echo -e "    aws ec2-instance-connect ssh --instance-id ${INSTANCE_ID} --os-user jfinlinson --connection-type eice"
echo ""
echo -e "  ${BLUE}Check Ziti tunnel status:${NC}"
echo -e "    ssh jfinlinson@${SERVER_ZITI_SSH} 'systemctl status ziti-edge-tunnel@${ZITI_IDENTITY}'"
echo ""
