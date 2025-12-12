#!/bin/bash
# =============================================================================
# Verify Deployment Logs Configuration
# =============================================================================
# After deployment, verifies that:
# 1. Application is sending logs to CloudWatch
# 2. Logs contain expected metadata (environment, instance_id)
# 3. Log retention is working
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"
LOG_GROUP="/theraprac/${ENVIRONMENT}/api"

echo -e "${GREEN}Verifying Deployment Logs for ${ENVIRONMENT}${NC}"
echo ""

# =============================================================================
# Test 1: Check Recent Logs Exist
# =============================================================================

echo -e "${YELLOW}[1/3] Checking for recent logs in CloudWatch...${NC}"

# Get logs from last 5 minutes
START_TIME=$(($(date +%s) - 300))
END_TIME=$(date +%s)

LOG_STREAMS=$(aws logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime \
    --descending \
    --max-items 5 \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'logStreams[*].logStreamName' \
    --output text 2>/dev/null || echo "")

if [ -z "$LOG_STREAMS" ]; then
    echo -e "  ${RED}✗${NC} No log streams found in $LOG_GROUP"
    echo "  This could mean:"
    echo "    - Application hasn't started yet"
    echo "    - CLOUDWATCH_LOG_GROUP not configured"
    echo "    - IAM permissions missing"
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Found log streams:"
for stream in $LOG_STREAMS; do
    echo "    - $stream"
done

# =============================================================================
# Test 2: Check Log Content
# =============================================================================

echo ""
echo -e "${YELLOW}[2/3] Checking log content for metadata...${NC}"

# Get most recent log stream
LATEST_STREAM=$(echo "$LOG_STREAMS" | awk '{print $1}')

if [ -n "$LATEST_STREAM" ]; then
    # Get recent log events
    LOG_EVENTS=$(aws logs get-log-events \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name "$LATEST_STREAM" \
        --start-time $((START_TIME * 1000)) \
        --limit 10 \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'events[*].message' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$LOG_EVENTS" ]; then
        echo -e "  ${YELLOW}⚠${NC} No recent log events found (may need to wait for logs)"
    else
        # Check for expected metadata
        HAS_ENV=false
        HAS_INSTANCE=false
        
        while IFS= read -r line; do
            if echo "$line" | grep -q '"environment"'; then
                HAS_ENV=true
            fi
            if echo "$line" | grep -q '"instance_id"'; then
                HAS_INSTANCE=true
            fi
        done <<< "$LOG_EVENTS"
        
        if [ "$HAS_ENV" = true ]; then
            echo -e "  ${GREEN}✓${NC} Logs contain environment metadata"
        else
            echo -e "  ${YELLOW}⚠${NC} Logs missing environment metadata"
        fi
        
        if [ "$HAS_INSTANCE" = true ]; then
            echo -e "  ${GREEN}✓${NC} Logs contain instance_id metadata"
        else
            echo -e "  ${YELLOW}⚠${NC} Logs missing instance_id metadata (may not be on EC2)"
        fi
        
        # Show sample log
        echo ""
        echo -e "  ${BLUE}Sample log entry:${NC}"
        echo "$LOG_EVENTS" | head -1 | jq -r '.' 2>/dev/null || echo "$LOG_EVENTS" | head -1
    fi
else
    echo -e "  ${YELLOW}⚠${NC} No log streams available"
fi

# =============================================================================
# Test 3: Verify Retention Policy
# =============================================================================

echo ""
echo -e "${YELLOW}[3/3] Verifying retention policy...${NC}"

EXPECTED_RETENTION=1
if [ "$ENVIRONMENT" == "prod" ]; then
    EXPECTED_RETENTION=30
fi

ACTUAL_RETENTION=$(aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query "logGroups[?logGroupName=='${LOG_GROUP}'].retentionInDays | [0]" \
    --output text)

if [ "$ACTUAL_RETENTION" == "$EXPECTED_RETENTION" ]; then
    echo -e "  ${GREEN}✓${NC} Retention policy: ${ACTUAL_RETENTION} day(s) (correct)"
else
    echo -e "  ${RED}✗${NC} Retention policy: ${ACTUAL_RETENTION} day(s) (expected ${EXPECTED_RETENTION})"
    exit 1
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${GREEN}✓ Deployment logs verification complete!${NC}"
echo ""
echo "View logs in CloudWatch:"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/${LOG_GROUP//\//%2F}"
echo ""
echo "Tail logs from CLI:"
echo "  aws logs tail ${LOG_GROUP} --follow --region ${AWS_REGION}"



