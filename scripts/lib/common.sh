#!/bin/bash
# =============================================================================
# TheraPrac Infrastructure - Common Shell Functions
# =============================================================================
# Shared helper functions for deployment scripts.
# Source this file: source "$(dirname "$0")/lib/common.sh"
# =============================================================================

# =============================================================================
# Colors
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
            # Wait for SSO session to initialize
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
                
                # Export credentials for Terraform
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

# Refresh AWS credentials (for long-running scripts)
refresh_aws_credentials() {
    local profile="${AWS_PROFILE:-jfinlinson_admin}"
    eval $(aws configure export-credentials --profile "$profile" --format env 2>/dev/null) || {
        echo -e "${RED}Failed to refresh credentials.${NC}"
        return 1
    }
}

# Get AWS account ID
get_aws_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# =============================================================================
# Interactive Prompts
# =============================================================================

# Prompt for a value with optional default
# Usage: prompt VAR_NAME "Prompt text" "default_value"
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

# Prompt for a choice from a list of options
# Usage: prompt_choice VAR_NAME "Prompt text" "opt1, opt2, opt3" "default"
prompt_choice() {
    local var_name="$1"
    local prompt_text="$2"
    local options="$3"
    local default_value="$4"
    local value

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
        if [ -n "$default_value" ]; then
            read -p "  Choice [$default_value]: " value
            value="${value:-$default_value}"
        else
            while [ -z "$value" ]; do
                read -p "  Choice: " value
            done
        fi
    fi

    eval "$var_name=\"$value\""
}

# Prompt for yes/no confirmation
# Usage: confirm "Do you want to continue?" && echo "yes" || echo "no"
confirm() {
    local prompt_text="$1"
    local default="${2:-n}"  # Default to no
    
    if [ "$NON_INTERACTIVE" = "true" ]; then
        echo -e "${BLUE}$prompt_text [y/N]: y (non-interactive)${NC}"
        return 0
    fi
    
    local reply
    read -p "$prompt_text [y/N] " -n 1 -r reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

# =============================================================================
# Cache Management
# =============================================================================

# Load cache file if it exists
# Usage: load_cache "/path/to/.cache-file"
load_cache() {
    local cache_file="$1"
    if [ -f "$cache_file" ]; then
        source "$cache_file"
        return 0
    fi
    return 1
}

# Save values to cache file
# Usage: save_cache "/path/to/.cache-file" "VAR1" "VAR2" "VAR3"
save_cache() {
    local cache_file="$1"
    shift
    local vars=("$@")
    
    {
        echo "# Cached values from last run"
        echo "# Generated: $(date)"
        for var in "${vars[@]}"; do
            local value="${!var}"
            echo "CACHED_${var}=\"${value}\""
        done
    } > "$cache_file"
    
    # Add to .gitignore if not already there
    local repo_root
    repo_root="$(dirname "$cache_file")"
    local cache_name
    cache_name="$(basename "$cache_file")"
    
    if [ -f "$repo_root/.gitignore" ] && ! grep -q "^${cache_name}$" "$repo_root/.gitignore"; then
        echo "$cache_name" >> "$repo_root/.gitignore"
    fi
}

# =============================================================================
# Terraform Helpers
# =============================================================================

# Check if Terraform has pending changes
# Returns: 0 = no changes, 1 = error, 2 = changes pending
terraform_check_changes() {
    local tf_dir="$1"
    local original_dir="$PWD"
    
    cd "$tf_dir" || return 1
    
    # Initialize if needed
    if [ ! -d ".terraform" ]; then
        echo -e "${YELLOW}Initializing Terraform...${NC}"
        terraform init -reconfigure >/dev/null 2>&1 || {
            cd "$original_dir"
            return 1
        }
    fi
    
    # Plan and check exit code
    terraform plan -detailed-exitcode >/dev/null 2>&1
    local exit_code=$?
    
    cd "$original_dir"
    return $exit_code
}

# Apply Terraform changes with confirmation
# Usage: terraform_apply "/path/to/tf/dir" [extra_vars...]
terraform_apply() {
    local tf_dir="$1"
    shift
    local extra_vars=("$@")
    local original_dir="$PWD"
    
    cd "$tf_dir" || return 1
    
    echo -e "${YELLOW}Planning Terraform changes...${NC}"
    
    local var_args=""
    for var in "${extra_vars[@]}"; do
        var_args="$var_args -var=\"$var\""
    done
    
    eval terraform plan $var_args -out=tfplan
    
    echo ""
    if confirm "Apply these Terraform changes?"; then
        echo -e "${YELLOW}Applying...${NC}"
        terraform apply tfplan
        rm -f tfplan
        echo -e "${GREEN}✓ Terraform apply complete${NC}"
        cd "$original_dir"
        return 0
    else
        rm -f tfplan
        echo -e "${YELLOW}Terraform apply skipped${NC}"
        cd "$original_dir"
        return 1
    fi
}

# =============================================================================
# Ansible Helpers
# =============================================================================

# Check if Ziti connection is available
check_ziti_connection() {
    local host="$1"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" exit 0 2>/dev/null
}

# Run Ansible playbook with proper inventory
# Usage: run_ansible_playbook "playbook.yml" "host_limit" "extra_vars..."
run_ansible_playbook() {
    local playbook="$1"
    local host_limit="$2"
    shift 2
    local extra_vars=("$@")
    
    local inventory="inventory/ziti.yml"
    
    # Build extra vars string
    local var_args=""
    for var in "${extra_vars[@]}"; do
        var_args="$var_args -e \"$var\""
    done
    
    echo -e "${YELLOW}Running Ansible playbook: $playbook${NC}"
    echo -e "  Host: $host_limit"
    echo ""
    
    eval ansible-playbook -i "$inventory" "$playbook" --limit "$host_limit" $var_args
}

# =============================================================================
# Utility Functions
# =============================================================================

# Print a section header
print_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=== $title ===${NC}"
    echo ""
}

# Print a banner
print_banner() {
    local title="$1"
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $(printf '%-60s' "$title")║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Print success banner
print_success_banner() {
    local title="$1"
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  $(printf '%-60s' "$title")║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
}




