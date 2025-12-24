# TheraPrac Infrastructure Documentation Authority Index

**Purpose:** Explicitly establish document authority levels for infrastructure documentation.

---

## Document Authority Levels

| Level | Meaning |
|-------|---------|
| **AUTHORITATIVE** | Source of truth. All operations must follow these documents. |
| **SUPPORTING** | Reference guides. Helpful but verify against authoritative sources. |

---

## AUTHORITATIVE Documents

| Document | Scope |
|----------|-------|
| `../README.md` | **Main entry point** - Quick start, helper scripts, project structure |
| `DEPLOYMENT_WORKFLOW.md` | **Deployment operations** - How all deployment scripts work together |
| `ZITI_RESOURCE_MANAGEMENT.md` | **Ziti operations** - Managing identities, services, policies |
| `ZITI_ROLES_AND_POLICIES.md` | **Ziti access control** - Role definitions, policy structure |

---

## SUPPORTING Documents

| Document | Purpose |
|----------|---------|
| `BRANCH_BUILD_DEPLOYMENT.md` | Branch build deployment guide |
| `BUILD_RETENTION_STRATEGY.md` | Build retention and cleanup |
| `CLOUDWATCH_LOGS_SETUP.md` | CloudWatch log configuration |
| `CREATE_ZITI_WEB_USER.md` | Ziti web user creation |
| `ZITI_CLEANUP.md` | Ziti resource cleanup |
| `ZITI_MANUAL_SETUP.md` | Manual Ziti setup (reference only) |

---

## Authority Collision Resolution

1. **DEPLOYMENT_WORKFLOW.md wins** for deployment procedures
2. **ZITI_RESOURCE_MANAGEMENT.md wins** for Ziti operations
3. Script `--help` output takes precedence over stale documentation

---

## Maintenance

Infrastructure documentation is operational. Keep it:
- Accurate to current scripts and procedures
- Minimal - only what operators need
- Updated when scripts change

---

**Last Updated:** 2024-12-24

