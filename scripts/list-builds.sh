#!/bin/bash
# =============================================================================
# List Available API Builds
# =============================================================================
# Lists all available builds in S3 with metadata (branch, commit, timestamp)
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
S3_BUCKET="${S3_BUCKET:-theraprac-api}"
AWS_PROFILE="${AWS_PROFILE:-jfinlinson_admin}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-30}"  # Only show builds from last N days
MAX_COMMITS_PER_BRANCH="${MAX_COMMITS_PER_BRANCH:-10}"  # Limit commits shown per branch

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Available API Builds${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Showing builds from last ${MAX_AGE_DAYS} days${NC}"
echo ""

# =============================================================================
# List Branch Builds
# =============================================================================
echo -e "${CYAN}Branch Builds:${NC}"
echo ""

# Get all branch paths that have a latest/manifest.json
BRANCH_PATHS=$(aws s3 ls "s3://${S3_BUCKET}/builds/" --profile "$AWS_PROFILE" --recursive 2>/dev/null | \
    grep "latest/manifest.json" | \
    sed 's|.*builds/\(.*\)/latest/manifest.json|\1|' | \
    sort -u)

if [ -z "$BRANCH_PATHS" ]; then
    echo -e "  ${YELLOW}No branch builds found${NC}"
else
    for BRANCH_PATH in $BRANCH_PATHS; do
        echo -e "  ${GREEN}Branch: ${BRANCH_PATH}${NC}"
        
        # Get latest manifest and validate
        TEMP_MANIFEST=$(mktemp)
        if aws s3 cp "s3://${S3_BUCKET}/builds/${BRANCH_PATH}/latest/manifest.json" "$TEMP_MANIFEST" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
            # Validate manifest has required fields
            if jq -e '.version and .commit_short and .build_timestamp' "$TEMP_MANIFEST" >/dev/null 2>&1; then
                VERSION=$(jq -r '.version' "$TEMP_MANIFEST" 2>/dev/null || echo "unknown")
                COMMIT_SHORT=$(jq -r '.commit_short' "$TEMP_MANIFEST" 2>/dev/null || echo "unknown")
                TIMESTAMP=$(jq -r '.build_timestamp' "$TEMP_MANIFEST" 2>/dev/null || echo "unknown")
                
                # Check if tarball exists
                TARBALL_PATH="builds/${BRANCH_PATH}/latest/theraprac-api-${VERSION}-linux-arm64.tar.gz"
                if aws s3 ls "s3://${S3_BUCKET}/${TARBALL_PATH}" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                    echo -e "    ${CYAN}latest${NC}:"
                    echo -e "      Version: ${VERSION}"
                    echo -e "      Commit:  ${COMMIT_SHORT}"
                    echo -e "      Built:   ${TIMESTAMP}"
                    echo -e "      Deploy:  ${GREEN}./scripts/deploy-api.sh <env> <server> ${BRANCH_PATH}/latest${NC}"
                else
                    echo -e "    ${YELLOW}latest${NC}: ${RED}⚠ Invalid (tarball missing)${NC}"
                fi
            else
                echo -e "    ${YELLOW}latest${NC}: ${RED}⚠ Invalid (manifest incomplete)${NC}"
            fi
        else
            echo -e "    ${YELLOW}latest${NC}: ${RED}⚠ Invalid (manifest missing)${NC}"
        fi
        rm -f "$TEMP_MANIFEST"
        
        # List recent commits (filter by date and limit count)
        CUTOFF_DATE=$(date -u -v-${MAX_AGE_DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${MAX_AGE_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
        
        COMMITS=$(aws s3 ls "s3://${S3_BUCKET}/builds/${BRANCH_PATH}/" --profile "$AWS_PROFILE" 2>/dev/null | \
            grep "PRE" | \
            grep -v "latest" | \
            awk '{print $2}' | \
            tr -d '/')
        
        if [ -n "$COMMITS" ]; then
            VALID_COMMITS=()
            for COMMIT in $COMMITS; do
                TEMP_MANIFEST=$(mktemp)
                if aws s3 cp "s3://${S3_BUCKET}/builds/${BRANCH_PATH}/${COMMIT}/manifest.json" "$TEMP_MANIFEST" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                    # Validate manifest has required fields
                    if jq -e '.version and .commit_short and .build_timestamp' "$TEMP_MANIFEST" >/dev/null 2>&1; then
                        VERSION=$(jq -r '.version' "$TEMP_MANIFEST" 2>/dev/null || echo "")
                        TIMESTAMP=$(jq -r '.build_timestamp' "$TEMP_MANIFEST" 2>/dev/null || echo "")
                        
                        # Check if tarball exists
                        TARBALL_PATH="builds/${BRANCH_PATH}/${COMMIT}/theraprac-api-${VERSION}-linux-arm64.tar.gz"
                        if aws s3 ls "s3://${S3_BUCKET}/${TARBALL_PATH}" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                            # Filter by date if cutoff is set
                            if [ -n "$CUTOFF_DATE" ] && [ -n "$TIMESTAMP" ]; then
                                if [[ "$TIMESTAMP" > "$CUTOFF_DATE" ]] || [[ "$TIMESTAMP" == "$CUTOFF_DATE" ]]; then
                                    VALID_COMMITS+=("${COMMIT}|${TIMESTAMP}|${VERSION}")
                                fi
                            else
                                # If date filtering fails, include it anyway
                                VALID_COMMITS+=("${COMMIT}|${TIMESTAMP}|${VERSION}")
                            fi
                        fi
                    fi
                fi
                rm -f "$TEMP_MANIFEST"
            done
            
            # Sort by timestamp (newest first) and limit
            if [ ${#VALID_COMMITS[@]} -gt 0 ]; then
                echo -e "    ${CYAN}Recent commits (showing ${MAX_COMMITS_PER_BRANCH} most recent from last ${MAX_AGE_DAYS} days):${NC}"
                
                # Sort by timestamp (second field after |)
                SORTED_COMMITS=($(printf '%s\n' "${VALID_COMMITS[@]}" | sort -t'|' -k2 -r | head -${MAX_COMMITS_PER_BRANCH}))
                
                for COMMIT_ENTRY in "${SORTED_COMMITS[@]}"; do
                    # Parse: commit|timestamp|version
                    COMMIT="${COMMIT_ENTRY%%|*}"
                    REST="${COMMIT_ENTRY#*|}"
                    TIMESTAMP="${REST%%|*}"
                    VERSION="${REST##*|}"
                    
                    echo -e "      ${COMMIT}: ${VERSION} (${TIMESTAMP})"
                    echo -e "        Deploy: ${GREEN}./scripts/deploy-api.sh <env> <server> ${BRANCH_PATH}/${COMMIT}${NC}"
                done
            fi
        fi
        echo ""
    done
fi

# =============================================================================
# List Releases
# =============================================================================
echo -e "${CYAN}Releases:${NC}"
echo ""

RELEASES=$(aws s3 ls "s3://${S3_BUCKET}/releases/" --profile "$AWS_PROFILE" 2>/dev/null | grep "PRE" | awk '{print $2}' | tr -d '/' | sort -Vr)

if [ -z "$RELEASES" ]; then
    echo -e "  ${YELLOW}No releases found${NC}"
else
    for RELEASE in $RELEASES; do
        TEMP_MANIFEST=$(mktemp)
        if aws s3 cp "s3://${S3_BUCKET}/releases/${RELEASE}/manifest.json" "$TEMP_MANIFEST" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
            # Validate manifest has required fields
            if jq -e '.version and .commit_short and .build_timestamp' "$TEMP_MANIFEST" >/dev/null 2>&1; then
                VERSION=$(jq -r '.version' "$TEMP_MANIFEST" 2>/dev/null || echo "unknown")
                COMMIT_SHORT=$(jq -r '.commit_short' "$TEMP_MANIFEST" 2>/dev/null || echo "unknown")
                TIMESTAMP=$(jq -r '.build_timestamp' "$TEMP_MANIFEST" 2>/dev/null || echo "unknown")
                
                # Check if tarball exists
                TARBALL_PATH="releases/${RELEASE}/theraprac-api-${VERSION}-linux-arm64.tar.gz"
                if aws s3 ls "s3://${S3_BUCKET}/${TARBALL_PATH}" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
                    # Extract version from release path (e.g., v0.1.0 -> 0.1.0)
                    RELEASE_VERSION="${RELEASE#v}"
                    echo -e "  ${GREEN}${RELEASE}${NC}:"
                    echo -e "    Version: ${VERSION}"
                    echo -e "    Commit:  ${COMMIT_SHORT}"
                    echo -e "    Built:   ${TIMESTAMP}"
                    echo -e "    Deploy:  ${GREEN}./scripts/deploy-api.sh <env> <server> ${RELEASE_VERSION}${NC}"
                else
                    echo -e "  ${YELLOW}${RELEASE}${NC}: ${RED}⚠ Invalid (tarball missing)${NC}"
                fi
            else
                echo -e "  ${YELLOW}${RELEASE}${NC}: ${RED}⚠ Invalid (manifest incomplete)${NC}"
            fi
        else
            echo -e "  ${YELLOW}${RELEASE}${NC}: ${RED}⚠ Invalid (manifest missing)${NC}"
        fi
        rm -f "$TEMP_MANIFEST"
        echo ""
    done
fi

echo -e "${BLUE}========================================${NC}"
