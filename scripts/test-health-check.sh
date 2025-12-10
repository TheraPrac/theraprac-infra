#!/bin/bash
# =============================================================================
# Test Health Check Script
# =============================================================================
# Isolated health check test to debug deployment issues
#
# Usage:
#   ./scripts/test-health-check.sh ssh.app.mt.dev.ziti
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get server host from argument or prompt
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 <server-host> [username]${NC}"
    echo "Example: $0 ssh.app.mt.dev.ziti"
    echo "Example: $0 ssh.app.mt.dev.ziti jfinlinson"
    exit 1
fi

SERVER_HOST="$1"
SSH_USER="${2:-ansible}"

# Try to detect which user works
if [ "$SSH_USER" = "ansible" ]; then
    if ! ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes "ansible@${SERVER_HOST}" "echo test" >/dev/null 2>&1; then
        if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes "jfinlinson@${SERVER_HOST}" "echo test" >/dev/null 2>&1; then
            SSH_USER="jfinlinson"
            echo -e "${YELLOW}Note: Using jfinlinson user (ansible not available)${NC}"
        fi
    fi
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Health Check Test${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Server: ${GREEN}${SERVER_HOST}${NC}"
echo ""

# Test 1: Check SSH connectivity
echo -e "${YELLOW}[1/5] Testing SSH connectivity as ${SSH_USER}...${NC}"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" "echo 'SSH OK'" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ SSH connection failed${NC}"
    echo "  Make sure Ziti Desktop Edge is running and you have access to ${SERVER_HOST}"
    exit 1
fi
echo ""

# Test 2: Check service status
echo -e "${YELLOW}[2/5] Checking service status...${NC}"
SERVICE_STATUS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
    "systemctl is-active theraprac-api 2>&1" || echo "inactive")
if [ "$SERVICE_STATUS" = "active" ]; then
    echo -e "${GREEN}✓ Service is active${NC}"
else
    echo -e "${RED}✗ Service is not active (status: ${SERVICE_STATUS})${NC}"
    echo ""
    echo "Service status details:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "systemctl status theraprac-api --no-pager -n 10" 2>&1 || true
    echo ""
    echo "Recent logs:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "journalctl -u theraprac-api -n 20 --no-pager" 2>&1 | tail -20 || true
    exit 1
fi
echo ""

# Test 3: Check if port is listening
echo -e "${YELLOW}[3/5] Checking if port 8080 is listening...${NC}"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
    "netstat -tln 2>/dev/null | grep -q ':8080 ' || ss -tln 2>/dev/null | grep -q ':8080 '" 2>/dev/null; then
    echo -e "${GREEN}✓ Port 8080 is listening${NC}"
else
    echo -e "${YELLOW}⚠ Port 8080 may not be listening (or netstat/ss not available)${NC}"
fi
echo ""

# Test 4: Try basic HTTP connection
echo -e "${YELLOW}[4/5] Testing HTTP connection to localhost:8080...${NC}"
HTTP_TEST=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
    "timeout 2 curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>&1" || echo "failed")
if [ "$HTTP_TEST" = "200" ] || [ "$HTTP_TEST" = "503" ]; then
    echo -e "${GREEN}✓ HTTP connection successful (status: ${HTTP_TEST})${NC}"
else
    echo -e "${RED}✗ HTTP connection failed (response: ${HTTP_TEST})${NC}"
    echo "  This could mean:"
    echo "  - Service is not listening on port 8080"
    echo "  - Service is still starting up"
    echo "  - Network/firewall issue"
fi
echo ""

# Test 5: Full health check with response
echo -e "${YELLOW}[5/5] Testing health endpoint with full response...${NC}"
echo "Attempting health check (this may take up to 60 seconds)..."
echo ""

HEALTH_OK=false
HEALTH_RESPONSE=""
for i in {1..30}; do
    HEALTH_RESPONSE=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "curl -sf http://localhost:8080/health 2>&1" || echo "")
    
    if [ $? -eq 0 ] && [ -n "$HEALTH_RESPONSE" ] && echo "$HEALTH_RESPONSE" | grep -q '"status"'; then
        HEALTH_OK=true
        echo -e "${GREEN}✓ Health check successful (attempt $i)${NC}"
        break
    fi
    
    if [ $i -eq 1 ]; then
        echo -n "Waiting"
    fi
    echo -n "."
    sleep 2
done
echo ""
echo ""

if [ "$HEALTH_OK" = "true" ]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Health Check PASSED${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Health check response:"
    echo "$HEALTH_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$HEALTH_RESPONSE"
    echo ""
else
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Health Check FAILED${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    if [ -n "$HEALTH_RESPONSE" ]; then
        echo "Last response received:"
        echo "$HEALTH_RESPONSE"
        echo ""
    else
        echo "No response received from health endpoint"
        echo ""
    fi
    
    echo "Diagnostics:"
    echo "  - Service status:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "systemctl status theraprac-api --no-pager -n 5" 2>&1 | head -15 || true
    echo ""
    echo "  - Recent logs:"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${SERVER_HOST}" \
        "journalctl -u theraprac-api -n 30 --no-pager" 2>&1 | tail -30 || true
    echo ""
    echo "  - Try manually:"
    echo "    ssh ${SSH_USER}@${SERVER_HOST} 'curl -v http://localhost:8080/health'"
    exit 1
fi

