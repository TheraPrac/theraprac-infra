#!/bin/bash
# =============================================================================
# List Available Web Builds
# =============================================================================
# Lists all available web builds in S3 with metadata (environment, branch, tag)
#
# S3 Structure:
#   builds/{env}/{branch}/{tag}/
#   builds/{env}/{branch}/latest/
#   releases/{tag}/
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
S3_BUCKET="${S3_BUCKET:-theraprac-web}"
AWS_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-30}"  # Only show builds from last N days
MAX_BUILDS_PER_BRANCH="${MAX_BUILDS_PER_BRANCH:-10}"  # Limit builds shown per branch

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Available Web Builds${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Showing builds from last ${MAX_AGE_DAYS} days${NC}"
echo ""

# =============================================================================
# Helper Functions
# =============================================================================

validate_manifest() {
    local manifest_path="$1"
    local temp_file=$(mktemp)
    
    if aws s3 cp "s3://${S3_BUCKET}/${manifest_path}" "$temp_file" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        if jq -e '.version and .environment and .branch and .build_timestamp' "$temp_file" >/dev/null 2>&1; then
            cat "$temp_file"
            rm -f "$temp_file"
            return 0
        fi
    fi
    rm -f "$temp_file"
    return 1
}

get_tarball_name() {
    local version="$1"
    local env="$2"
    echo "theraprac-web-${version}-${env}.tar.gz"
}

# =============================================================================
# List Environment Builds
# =============================================================================

for ENV in dev test prod; do
    echo -e "${CYAN}Environment: ${ENV}${NC}"
    echo ""
    
    # Check if environment directory exists
    if ! aws s3 ls "s3://${S3_BUCKET}/builds/${ENV}/" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}No ${ENV} builds found${NC}"
        echo ""
        continue
    fi
    
    # Get all branches for this environment
    BRANCHES=$(aws s3 ls "s3://${S3_BUCKET}/builds/${ENV}/" --profile "$AWS_PROFILE" 2>/dev/null | \
        grep "PRE" | awk '{print $2}' | tr -d '/' | sort)
    
    if [ -z "$BRANCHES" ]; then
        echo -e "  ${YELLOW}No ${ENV} builds found${NC}"
        echo ""
        continue
    fi
    
    for BRANCH in $BRANCHES; do
        echo -e "  ${GREEN}Branch: ${BRANCH}${NC}"
        
        # Check for latest pointer
        LATEST_MANIFEST=$(validate_manifest "builds/${ENV}/${BRANCH}/latest/manifest.json")
        if [ -n "$LATEST_MANIFEST" ]; then
            VERSION=$(echo "$LATEST_MANIFEST" | jq -r '.version')
            TAG=$(echo "$LATEST_MANIFEST" | jq -r '.tag')
            COMMIT_SHORT=$(echo "$LATEST_MANIFEST" | jq -r '.commit_short')
            TIMESTAMP=$(echo "$LATEST_MANIFEST" | jq -r '.build_timestamp')
            TARBALL_NAME=$(get_tarball_name "$VERSION" "$ENV")
            
            # Verify tarball exists
            if aws s3 ls "s3://${S3_BUCKET}/builds/${ENV}/${BRANCH}/latest/${TARBALL_NAME}" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                echo -e "    ${CYAN}latest${NC}:"
                echo -e "      Tag:     ${TAG}"
                echo -e "      Version: ${VERSION}"
                echo -e "      Commit:  ${COMMIT_SHORT}"
                echo -e "      Built:   ${TIMESTAMP}"
                echo -e "      Deploy:  ${GREEN}./scripts/deploy-web.sh ${ENV} <server> ${BRANCH}/latest${NC}"
            else
                echo -e "    ${YELLOW}latest${NC}: ${RED}⚠ Invalid (tarball missing)${NC}"
            fi
        else
            echo -e "    ${YELLOW}latest${NC}: ${RED}⚠ Invalid (manifest missing/incomplete)${NC}"
        fi
        
        # List specific tag builds
        TAGS=$(aws s3 ls "s3://${S3_BUCKET}/builds/${ENV}/${BRANCH}/" --profile "$AWS_PROFILE" 2>/dev/null | \
            grep "PRE" | grep -v "latest" | awk '{print $2}' | tr -d '/' | sort -Vr)
        
        if [ -n "$TAGS" ]; then
            echo -e "    ${CYAN}Recent builds:${NC}"
            
            COUNT=0
            CUTOFF_DATE=$(date -u -v-${MAX_AGE_DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${MAX_AGE_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
            
            for TAG in $TAGS; do
                [ $COUNT -ge $MAX_BUILDS_PER_BRANCH ] && break
                
                MANIFEST=$(validate_manifest "builds/${ENV}/${BRANCH}/${TAG}/manifest.json")
                if [ -n "$MANIFEST" ]; then
                    VERSION=$(echo "$MANIFEST" | jq -r '.version')
                    TIMESTAMP=$(echo "$MANIFEST" | jq -r '.build_timestamp')
                    COMMIT_SHORT=$(echo "$MANIFEST" | jq -r '.commit_short')
                    TARBALL_NAME=$(get_tarball_name "$VERSION" "$ENV")
                    
                    # Filter by date
                    if [ -n "$CUTOFF_DATE" ] && [ -n "$TIMESTAMP" ]; then
                        if [[ ! "$TIMESTAMP" > "$CUTOFF_DATE" ]] && [[ "$TIMESTAMP" != "$CUTOFF_DATE" ]]; then
                            continue
                        fi
                    fi
                    
                    # Verify tarball exists
                    if aws s3 ls "s3://${S3_BUCKET}/builds/${ENV}/${BRANCH}/${TAG}/${TARBALL_NAME}" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                        echo -e "      ${TAG}: ${VERSION} (${COMMIT_SHORT}) - ${TIMESTAMP}"
                        echo -e "        Deploy: ${GREEN}./scripts/deploy-web.sh ${ENV} <server> ${BRANCH}/${TAG}${NC}"
                        ((COUNT++))
                    fi
                fi
            done
            
            if [ $COUNT -eq 0 ]; then
                echo -e "      ${YELLOW}No valid builds in last ${MAX_AGE_DAYS} days${NC}"
            fi
        fi
        echo ""
    done
done

# =============================================================================
# List Releases
# =============================================================================
echo -e "${CYAN}Releases (immutable):${NC}"
echo ""

RELEASES=$(aws s3 ls "s3://${S3_BUCKET}/releases/" --profile "$AWS_PROFILE" 2>/dev/null | \
    grep "PRE" | awk '{print $2}' | tr -d '/' | sort -Vr)

if [ -z "$RELEASES" ]; then
    echo -e "  ${YELLOW}No releases found${NC}"
else
    for RELEASE in $RELEASES; do
        MANIFEST=$(validate_manifest "releases/${RELEASE}/manifest.json")
        if [ -n "$MANIFEST" ]; then
            VERSION=$(echo "$MANIFEST" | jq -r '.version')
            ENV=$(echo "$MANIFEST" | jq -r '.environment')
            BRANCH=$(echo "$MANIFEST" | jq -r '.branch')
            COMMIT_SHORT=$(echo "$MANIFEST" | jq -r '.commit_short')
            TIMESTAMP=$(echo "$MANIFEST" | jq -r '.build_timestamp')
            TARBALL_NAME=$(get_tarball_name "$VERSION" "$ENV")
            
            # Verify tarball exists
            if aws s3 ls "s3://${S3_BUCKET}/releases/${RELEASE}/${TARBALL_NAME}" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                echo -e "  ${GREEN}${RELEASE}${NC}:"
                echo -e "    Version: ${VERSION}"
                echo -e "    Branch:  ${BRANCH}"
                echo -e "    Commit:  ${COMMIT_SHORT}"
                echo -e "    Built:   ${TIMESTAMP}"
                echo -e "    Deploy:  ${GREEN}./scripts/deploy-web.sh prod <server> ${RELEASE}${NC}"
            else
                echo -e "  ${YELLOW}${RELEASE}${NC}: ${RED}⚠ Invalid (tarball missing)${NC}"
            fi
        else
            echo -e "  ${YELLOW}${RELEASE}${NC}: ${RED}⚠ Invalid (manifest missing/incomplete)${NC}"
        fi
        echo ""
    done
fi

echo -e "${BLUE}========================================${NC}"

