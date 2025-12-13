# Build Artifact Retention Strategy

## Problem

As builds accumulate, listing all builds becomes unwieldy. We need:
1. **Automatic cleanup** of old builds (infrastructure)
2. **Smart filtering** in scripts (user experience)
3. **Clear retention policies** (methodology)

## Solution: Multi-Layer Approach

### 1. S3 Lifecycle Policies (Infrastructure)

**Automatic cleanup at the bucket level:**

- **Branch builds**: Delete after 30 days
- **Releases**: Keep forever (immutable)
- **Latest pointers**: Keep forever (always point to most recent)

**Implementation:**
- Terraform module to manage S3 lifecycle rules
- Separate rules for `builds/` vs `releases/`
- No manual intervention needed

### 2. Script Filtering (User Experience)

**Display only relevant builds:**

- **Recent builds only**: Show builds from last N days (default: 30)
- **Limit per branch**: Show max 10 most recent commits per branch
- **Valid builds only**: Only show builds with valid manifests
- **Releases always shown**: All releases are always visible

**Implementation:**
- `list-builds.sh` filters by date
- `deploy-api.sh` validates build exists before deploying

### 3. Naming & Organization (Methodology)

**Current structure is good, but we can improve:**

```
builds/
  {branch}/
    {commit}/          # Individual build (auto-deleted after 30 days)
    latest/            # Pointer to most recent (kept forever)
releases/
  v{version}/          # Tagged release (kept forever)
```

**Optional enhancements:**
- Add build tags/metadata for "keep" builds
- Date-based organization (if needed later)
- Build status indicators (success/failure)

## Recommended Retention Periods

| Build Type | Retention | Rationale |
|------------|-----------|-----------|
| Branch builds (individual commits) | 30 days | Enough for rollback, not cluttered |
| Branch `latest` pointers | Forever | Always need to know "latest" |
| Releases | Forever | Immutable, permanent record |
| Failed builds | 7 days | Debug issues, then cleanup |

## Implementation Priority

1. **Script filtering** (immediate) - Easy win, improves UX now
2. **S3 lifecycle policies** (next) - Prevents storage bloat
3. **Build tagging** (future) - For special builds that need longer retention




