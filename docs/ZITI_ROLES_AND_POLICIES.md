# Ziti Roles and Policies Reference

Current state of Ziti role attributes, services, and policies in the TheraPrac infrastructure.

## Identity Roles (Who Can Access)

| Role | Purpose | Assigned To | Example Identities |
|------|---------|-------------|---------------------|
| `users` | All human users | User identities | `jane-dev`, `joe-dev` |
| `developers` | Developer team members | Developer identities | `jane-dev`, `joe-dev` |
| `ssh-users` | Can dial SSH services | Users needing SSH access | `jane-dev`, `joe-dev` |
| `routers` | Edge routers that bind services | Router identities | `ziti-router-nonprod` |
| `tunnelers` | Routers with tunneler enabled | Router identities | `ziti-router-nonprod` |
| `basic-servers` | Basic server identities (can bind services) | Server identities | `basic-server-app-mt-nonprod`, `basic-server-ziti-edge-router-nonprod` |

## Service Roles (What Services Exist)

| Service Role | Purpose | Services With This Role |
|--------------|---------|------------------------|
| `ssh-services` | SSH service category | `ssh-nonprod`, `ssh.ziti-nonprod.ziti` |
| `basic-server-ssh` | Basic server SSH services | `ssh.app.mt.nonprod.ziti`, `ssh.ziti.edge-router.nonprod.ziti` |
| `web-services` | Web application services | `app-dev.theraprac.com`, `app-test.theraprac.com` |
| `api-services` | API services | `api-dev.theraprac.com`, `api-test.theraprac.com` |
| `db-services` | Database services (PostgreSQL) | `postgres.db.dev.app.ziti` |

## Service Policies (Who Can Dial What)

### SSH Services

| Policy Name | Type | Identity Roles (Who) | Service Roles (What) | Purpose |
|-------------|------|---------------------|---------------------|---------|
| `ssh-bind` | Bind | `#routers` | `#ssh-services` | Routers can bind SSH services |
| `ssh-dial` | Dial | `#ssh-users` | `#ssh-services` | SSH users can dial SSH services |
| `basic-server-ssh-dial` | Dial | `#ssh-users` | `#basic-server-ssh` | SSH users can dial basic server SSH |
| `{service-name}-bind` | Bind | `@{identity-name}` | `@{service-name}` | Specific identity can bind specific service |

### HTTPS Services

| Policy Name | Type | Identity Roles (Who) | Service Roles (What) | Purpose |
|-------------|------|---------------------|---------------------|---------|
| `https-web-dial` | Dial | `#users` (default) | `#web-services` | All users can dial web services |
| `https-api-dial` | Dial | `#users` (default) | `#api-services` | All users can dial API services |

**Note**: The default `dial_identity_roles` is `#users`, but can be customized (e.g., `#users,#developers`).

## Edge Router Policies (Who Can Use Which Routers)

| Policy Name | Identity Roles (Who) | Edge Router Roles (Which Routers) | Purpose |
|-------------|---------------------|----------------------------------|---------|
| `users-to-routers` | `#users` | `#all` | All users can access all routers |
| `basic-servers-routers` | `#basic-servers` | `#routers` | Basic servers can use routers |

## Service-Edge-Router Policies (Which Services Can Use Which Routers)

| Policy Name | Service Roles (Which Services) | Edge Router Roles (Which Routers) | Purpose |
|-------------|-------------------------------|----------------------------------|---------|
| `basic-server-ssh-serp` | `#basic-server-ssh` | `#all` | Basic server SSH services can use all routers |
| `https-services-serp` | `#web-services,#api-services` | `#all` | HTTPS services can use all routers |
| `postgres.db.dev.app.ziti-serp` | `#db-services` | `#all` | Database services can use all routers |

## Database Service Policies (Identity-Based)

Database access uses **identity-based policies** instead of role-based for stricter access control.

| Policy Name | Type | Identities (Who) | Services (What) | Purpose |
|-------------|------|------------------|-----------------|---------|
| `postgres.db.dev.app.ziti-bind` | Bind | `@ziti.edge-router.nonprod` | `@postgres.db.dev.app.ziti` | Edge-router hosts the service |
| `postgres.db.dev.app.ziti-dial` | Dial | `@joe-dev`, `@app.mt.dev` | `@postgres.db.dev.app.ziti` | Only these identities can connect |

**Note**: Unlike SSH and HTTPS services which use role-based policies (`#ssh-users`, `#users`), database access is explicitly granted to specific identities for security.

## Example Identity Setup

```bash
# Create a developer identity with multiple roles
ansible-playbook create-identity.yml \
  -e "identity_name=jane-dev" \
  -e "identity_roles=users,developers,ssh-users"

# This identity can:
# - Access all routers (users role)
# - Dial SSH services (ssh-users role)
# - Dial web/API services (users role)
```

## Current Pattern Summary

1. **Service Role Naming**: `{category}-services` (e.g., `ssh-services`, `web-services`, `api-services`)
2. **Identity Role Naming**: `{category}-users` (e.g., `ssh-users`) or general (`users`, `developers`)
3. **Dial Policies**: Named `{service-category}-dial` (e.g., `ssh-dial`, `https-web-dial`)
4. **Bind Policies**: Named `{service-name}-bind` (specific) or `{category}-bind` (shared)

## Database Service Implementation

The database service uses **identity-based access control** for security:

### Service Configuration
- **Service Name**: `postgres.db.dev.app.ziti`
- **Service Role**: `db-services`
- **Host Config**: Points to RDS endpoint on port 5432
- **Intercept Config**: Clients dial `postgres.db.dev.app.ziti:5432`

### Access Control (Identity-Based)
Unlike SSH and HTTPS which use role-based policies, database access is explicitly granted:

| Identity | Access | Purpose |
|----------|--------|---------|
| `ziti.edge-router.nonprod` | Bind | Hosts the service (forwards to RDS) |
| `joe-dev` | Dial | Developer access for migrations, debugging |
| `app.mt.dev` | Dial | Application server database connection |

### Adding New Database Users

To grant database access to a new identity:

```bash
# SSH to controller
ssh jfinlinson@ssh.ziti-nonprod.ziti

# Login to Ziti
ziti edge login https://ziti-nonprod.theraprac.com:443 --username admin --password $(sudo cat /opt/ziti/controller/.admin_password) --yes

# Update the dial policy to include new identity
ziti edge update service-policy postgres.db.dev.app.ziti-dial \
  --identity-roles '@joe-dev,@app.mt.dev,@new-identity'
```

### Connection Information

```bash
# From authorized identity (joe-dev or app.mt.dev)
psql -h postgres.db.dev.app.ziti -p 5432 -U theraprac -d theraprac
# SSL Mode: require (RDS enforces TLS)
```

