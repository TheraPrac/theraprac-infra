#!/bin/bash
# =============================================================================
# TheraPrac AWS SSO Authentication Helper
# =============================================================================
# This script exports AWS SSO credentials to environment variables for use
# with Terraform and Ansible.
#
# Usage:
#   source scripts/aws-auth.sh
#   # or
#   eval "$(scripts/aws-auth.sh)"
# =============================================================================

set -e

AWS_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"

# Check for AWS CLI v2
if ! aws --version 2>&1 | grep -q "aws-cli/2"; then
    echo "ERROR: AWS CLI v2 is required. Please install it first."
    echo "  brew install awscli"
    exit 1
fi

# Check if already authenticated
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1; then
    echo "AWS SSO session expired or not logged in."
    echo "Running: aws sso login --profile $AWS_PROFILE"
    aws sso login --profile "$AWS_PROFILE"
fi

# Export credentials to environment
echo "Exporting AWS credentials from profile: $AWS_PROFILE"
eval "$(aws configure export-credentials --profile "$AWS_PROFILE" --format env)"

# Verify authentication
IDENTITY=$(aws sts get-caller-identity --output text --query 'Arn' 2>/dev/null)
if [ -n "$IDENTITY" ]; then
    echo "✓ AWS authentication successful!"
    echo "  Identity: $IDENTITY"
    echo ""
    echo "Credentials exported to environment. You can now run:"
    echo "  terraform plan"
    echo "  ansible-playbook -i inventory/aws_ssm.yml playbook.yml"
else
    echo "ERROR: Failed to authenticate"
    exit 1
fi





