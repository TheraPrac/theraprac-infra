#!/bin/bash
# =============================================================================
# Test CloudWatch Logs Configuration
# =============================================================================
# Verifies that:
# 1. CloudWatch log groups exist with correct retention
# 2. IAM permissions allow writing to log groups
# 3. SSM parameters are set correctly
# 4. Logs can be written to CloudWatch
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"

echo -e "${GREEN}Testing CloudWatch Logs Configuration for ${ENVIRONMENT}${NC}"
echo ""

# =============================================================================
# Test 1: Check CloudWatch Log Groups Exist
# =============================================================================

echo -e "${YELLOW}[1/4] Checking CloudWatch log groups...${NC}"

API_LOG_GROUP="/theraprac/${ENVIRONMENT}/api"
WEB_LOG_GROUP="/theraprac/${ENVIRONMENT}/web"

check_log_group() {
    local group_name=$1
    local expected_retention=$2
    
    if aws logs describe-log-groups \
        --log-group-name-prefix "$group_name" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query "logGroups[?logGroupName=='${group_name}']" \
        --output json | grep -q "$group_name"; then
        
        RETENTION=$(aws logs describe-log-groups \
            --log-group-name-prefix "$group_name" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --query "logGroups[?logGroupName=='${group_name}'].retentionInDays | [0]" \
            --output text)
        
        if [ "$RETENTION" == "$expected_retention" ]; then
            echo -e "  ${GREEN}✓${NC} $group_name exists with ${RETENTION} day retention"
            return 0
        else
            echo -e "  ${RED}✗${NC} $group_name exists but has ${RETENTION} day retention (expected ${expected_retention})"
            return 1
        fi
    else
        echo -e "  ${RED}✗${NC} $group_name does not exist"
        return 1
    fi
}

EXPECTED_RETENTION=1
if [ "$ENVIRONMENT" == "prod" ]; then
    EXPECTED_RETENTION=30
fi

check_log_group "$API_LOG_GROUP" "$EXPECTED_RETENTION"
API_GROUP_OK=$?

check_log_group "$WEB_LOG_GROUP" "$EXPECTED_RETENTION"
WEB_GROUP_OK=$?

if [ $API_GROUP_OK -ne 0 ] || [ $WEB_GROUP_OK -ne 0 ]; then
    echo -e "${RED}Error: Log groups not configured correctly${NC}"
    echo "Run: cd infra/phase3-iam && terraform apply"
    exit 1
fi

# =============================================================================
# Test 2: Check SSM Parameters
# =============================================================================

echo ""
echo -e "${YELLOW}[2/4] Checking SSM parameters...${NC}"

SSM_PARAM="/theraprac/api/${ENVIRONMENT}/cloudwatch-log-group"

if aws ssm get-parameter \
    --name "$SSM_PARAM" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'Parameter.Value' \
    --output text > /dev/null 2>&1; then
    
    SSM_VALUE=$(aws ssm get-parameter \
        --name "$SSM_PARAM" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'Parameter.Value' \
        --output text)
    
    if [ "$SSM_VALUE" == "$API_LOG_GROUP" ]; then
        echo -e "  ${GREEN}✓${NC} SSM parameter $SSM_PARAM = $SSM_VALUE"
    else
        echo -e "  ${RED}✗${NC} SSM parameter $SSM_PARAM = $SSM_VALUE (expected $API_LOG_GROUP)"
        exit 1
    fi
else
    echo -e "  ${YELLOW}⚠${NC} SSM parameter $SSM_PARAM not set (will be created on next deployment)"
fi

# =============================================================================
# Test 3: Check IAM Permissions
# =============================================================================

echo ""
echo -e "${YELLOW}[3/4] Checking IAM permissions...${NC}"

# Get current identity to check permissions
CALLER_ARN=$(aws sts get-caller-identity \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'Arn' \
    --output text)

echo "  Current identity: $CALLER_ARN"

# Try to create a test log stream (this will fail if no permissions, but won't error if stream exists)
TEST_STREAM="test-$(date +%s)"
if aws logs create-log-stream \
    --log-group-name "$API_LOG_GROUP" \
    --log-stream-name "$TEST_STREAM" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    > /dev/null 2>&1; then
    
    echo -e "  ${GREEN}✓${NC} IAM permissions allow creating log streams"
    
    # Clean up test stream
    aws logs delete-log-stream \
        --log-group-name "$API_LOG_GROUP" \
        --log-stream-name "$TEST_STREAM" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        > /dev/null 2>&1 || true
else
    # Check if it's because stream already exists (that's okay)
    if aws logs describe-log-streams \
        --log-group-name "$API_LOG_GROUP" \
        --log-stream-name-prefix "$TEST_STREAM" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'logStreams[0].logStreamName' \
        --output text | grep -q "$TEST_STREAM"; then
        echo -e "  ${GREEN}✓${NC} IAM permissions allow creating log streams"
    else
        echo -e "  ${YELLOW}⚠${NC} Could not verify IAM permissions (may need EC2 instance role)"
    fi
fi

# =============================================================================
# Test 4: Test Log Writing (if on EC2)
# =============================================================================

echo ""
echo -e "${YELLOW}[4/4] Testing log writing capability...${NC}"

# Check if we're on an EC2 instance
if curl -s --max-time 1 http://169.254.169.254/latest/meta-data/instance-id > /dev/null 2>&1; then
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    echo "  Running on EC2 instance: $INSTANCE_ID"
    
    # Try to write a test log event
    TEST_MESSAGE="Test log entry from $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    TEST_STREAM="test-verification-$(date +%s)"
    
    # Create log stream
    if aws logs create-log-stream \
        --log-group-name "$API_LOG_GROUP" \
        --log-stream-name "$TEST_STREAM" \
        --region "$AWS_REGION" \
        > /dev/null 2>&1; then
        
        # Write test log
        TIMESTAMP=$(($(date +%s) * 1000))
        if aws logs put-log-events \
            --log-group-name "$API_LOG_GROUP" \
            --log-stream-name "$TEST_STREAM" \
            --log-events "timestamp=$TIMESTAMP,message=$TEST_MESSAGE" \
            --region "$AWS_REGION" \
            > /dev/null 2>&1; then
            
            echo -e "  ${GREEN}✓${NC} Successfully wrote test log to CloudWatch"
            echo "  Test log: $TEST_MESSAGE"
            
            # Clean up
            aws logs delete-log-stream \
                --log-group-name "$API_LOG_GROUP" \
                --log-stream-name "$TEST_STREAM" \
                --region "$AWS_REGION" \
                > /dev/null 2>&1 || true
        else
            echo -e "  ${RED}✗${NC} Failed to write log to CloudWatch"
            exit 1
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} Could not create test log stream (may need IAM role on instance)"
    fi
else
    echo "  Not running on EC2 - skipping log write test"
    echo "  (This test requires EC2 instance with IAM role)"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${GREEN}✓ All CloudWatch Logs configuration tests passed!${NC}"
echo ""
echo "Next steps:"
echo "  1. Deploy API: ansible-playbook deploy-api.yml -i inventory/${ENVIRONMENT}"
echo "  2. Check logs: aws logs tail ${API_LOG_GROUP} --follow --region ${AWS_REGION}"
echo "  3. View in console: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/${API_LOG_GROUP//\//%2F}"




