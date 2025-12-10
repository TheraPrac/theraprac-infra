# Creating Ziti Users for Dev Environment Web Access

This guide explains how to create new Ziti users that need access to the dev environment web application only.

## Overview

The script `create-ziti-web-user.sh` creates a new Ziti identity with the `users` role attribute, which grants access to both web and API services in the dev environment:
- Web application: `app-dev.theraprac.com` (via `https-web-dial` policy)
- API: `api-dev.theraprac.com` (via `https-api-dial` policy)

The API access is essential because the web application makes API calls to function properly.

### What Access is Granted

✅ **Granted:**
- Access to dev environment web application: `https://app-dev.theraprac.com`
- Access to dev environment API: `https://api-dev.theraprac.com` (required for web app to function)

**Note:** The `users` role grants access to both web and API services via the `https-web-dial` and `https-api-dial` policies. The API access is essential because the web application makes API calls to function properly.

❌ **NOT Granted:**
- SSH access to servers
- Database access
- Access to test or production environments

## Prerequisites

### Required Tools

1. **Ziti CLI** - Must be installed and in your PATH
   - Installation: https://openziti.io/docs/core-tools/cli-installation
   - Verify: `ziti --version`

2. **AWS CLI** - Must be installed and configured
   - Installation: https://aws.amazon.com/cli/
   - Verify: `aws --version`

3. **AWS Credentials** - Must have access to Secrets Manager
   - Secret path: `ziti/nonprod/admin-password`
   - Region: `us-west-2`
   - Verify: `aws sts get-caller-identity`

4. **jq** - JSON processor (usually pre-installed on macOS/Linux)
   - Verify: `jq --version`

### Required Permissions

- AWS Secrets Manager: Read access to `ziti/nonprod/admin-password`
- Ziti Controller: Admin access (via the password from Secrets Manager)

## Usage

### Basic Usage

```bash
cd theraprac-infra
./scripts/create-ziti-web-user.sh <identity-name>
```

### Example

```bash
./scripts/create-ziti-web-user.sh jane-dev
```

### Identity Name Requirements

- Must contain only alphanumeric characters, dashes (`-`), and underscores (`_`)
- Examples of valid names:
  - `jane-dev`
  - `john_doe`
  - `user-123`
- Examples of invalid names:
  - `jane.dev` (contains period)
  - `jane dev` (contains space)
  - `jane@dev` (contains special character)

## What the Script Does

1. **Validates Input**
   - Checks that identity name is provided
   - Validates identity name format
   - Verifies required tools are installed

2. **Retrieves Credentials**
   - Fetches Ziti admin password from AWS Secrets Manager
   - Verifies AWS credentials are valid

3. **Connects to Ziti**
   - Logs in to the Ziti controller at `ziti-nonprod.theraprac.com:443`

4. **Checks for Existing Identity**
   - Verifies the identity name is not already in use
   - Prevents duplicate identities

5. **Creates Identity**
   - Creates new identity with `users` role attribute
   - Generates JWT enrollment file (`<identity-name>.jwt`)

6. **Provides Instructions**
   - Displays enrollment instructions for the user
   - Shows what access has been granted

## Output

### JWT File

The script creates a JWT (JSON Web Token) file in the repository root:

```
theraprac-infra/
  └── <identity-name>.jwt
```

**Important:** This JWT file contains sensitive enrollment information. It should be:
- Securely transferred to the user
- Deleted after enrollment (optional, but recommended)
- Never committed to version control (should be in `.gitignore`)

### Example Output

```
╔══════════════════════════════════════════════════════════════╗
║  Create Ziti User - Dev Environment Web Access            ║
╚══════════════════════════════════════════════════════════════╝

Identity Name: jane-dev
Role Attributes: users
Access: Dev environment web services (app-dev.theraprac.com)

Retrieving Ziti admin password from AWS Secrets Manager...
✓ Password retrieved

Logging in to Ziti controller...
✓ Logged in successfully

Checking if identity already exists...
✓ Identity name is available

Creating identity with role attributes...
✓ Identity created successfully

╔══════════════════════════════════════════════════════════════╗
║  Identity Created Successfully                              ║
╚══════════════════════════════════════════════════════════════╝

Identity Details:
  Name: jane-dev
  Role Attributes: users
  JWT File: /path/to/theraprac-infra/jane-dev.jwt

Access Granted:
  • Dev environment web application: https://app-dev.theraprac.com

Next Steps - Enrollment:
...
```

## User Enrollment

After creating the identity, the user must enroll it on their machine. There are two enrollment methods:

### Method 1: Ziti CLI Enrollment

1. **Transfer the JWT file** to the user's machine:
   ```bash
   scp jane-dev.jwt user@machine:~/
   ```

2. **On the user's machine**, enroll the identity:
   ```bash
   ziti edge enroll ~/jane-dev.jwt -o ~/.config/ziti/identities/jane-dev.json
   ```

3. **Verify enrollment**:
   ```bash
   ziti edge list identities
   ```

### Method 2: Ziti Desktop Edge (ZDE) Enrollment

1. **Transfer the JWT file** to the user's machine (same as above)

2. **Open Ziti Desktop Edge** application

3. **Add Identity**:
   - Click the "Add Identity" or "+" button
   - Select "Import from File"
   - Choose the JWT file (`jane-dev.jwt`)

4. **Verify**: The identity should appear in ZDE and be automatically enrolled

## Testing Access

Once enrolled, the user can test their access:

```bash
# Test web application (requires ZDE running or ziti tunnel)
curl https://app-dev.theraprac.com/api/health

# Test API directly (requires ZDE running or ziti tunnel)
curl https://api-dev.theraprac.com/health

# Or open in browser (requires ZDE running)
# Navigate to: https://app-dev.theraprac.com
```

**Note:** The web application requires API access to function. Both services are accessible with the `users` role.

## Troubleshooting

### Error: Identity Already Exists

```
Error: Identity 'jane-dev' already exists

To remove the existing identity:
  ziti edge delete identity jane-dev
```

**Solution:** Either use a different identity name, or delete the existing identity if it's no longer needed.

### Error: Failed to Retrieve Admin Password

```
Error: Failed to retrieve admin password from Secrets Manager
```

**Possible causes:**
- AWS credentials not configured or expired
- Insufficient permissions to access Secrets Manager
- Secret doesn't exist

**Solution:**
1. Verify AWS credentials: `aws sts get-caller-identity`
2. Check AWS profile: `echo $AWS_PROFILE`
3. Login to AWS SSO if needed: `aws sso login --profile jfinlinson_admin`
4. Verify secret exists: `aws secretsmanager describe-secret --secret-id ziti/nonprod/admin-password`

### Error: Failed to Login to Ziti Controller

```
Error: Failed to login to Ziti controller
```

**Possible causes:**
- Ziti controller is down or unreachable
- Network connectivity issues
- Incorrect endpoint configuration

**Solution:**
1. Verify controller is accessible: `curl -k https://ziti-nonprod.theraprac.com/edge/client/v1/version`
2. Check network connectivity
3. Verify endpoint configuration in the script

### Error: Ziti CLI Not Found

```
Error: 'ziti' command not found
```

**Solution:** Install the Ziti CLI:
- macOS: `brew install openziti/ziti/ziti`
- Linux: Download from https://github.com/openziti/ziti/releases
- Or follow: https://openziti.io/docs/core-tools/cli-installation

### User Cannot Access Web Application

**Possible causes:**
- Identity not enrolled
- ZDE not running
- Wrong role attributes
- Policy not configured correctly

**Solution:**
1. Verify identity is enrolled: `ziti edge list identities`
2. Check ZDE is running (if using ZDE)
3. Verify role attributes: `ziti edge show identity jane-dev`
4. Check dial policy: `ziti edge show service-policy https-web-dial`

## Advanced Usage

### Creating Multiple Users

You can create multiple users in a loop:

```bash
for user in jane-dev john-dev mary-dev; do
  ./scripts/create-ziti-web-user.sh "$user"
done
```

### Non-Interactive Mode

The script is designed to be interactive, but you can use it in scripts by ensuring:
- AWS credentials are pre-configured
- All prerequisites are met
- Identity names are validated beforehand

## Related Documentation

- [Ziti Roles and Policies](./ZITI_ROLES_AND_POLICIES.md) - Understanding role attributes and policies
- [Ziti Manual Setup](./ZITI_MANUAL_SETUP.md) - Historical setup documentation
- [Ziti Resource Management](./ZITI_RESOURCE_MANAGEMENT.md) - Managing Ziti resources

## Security Considerations

1. **JWT Files**: JWT files contain sensitive enrollment tokens. They should be:
   - Transferred securely (e.g., via encrypted channels)
   - Deleted after enrollment (optional but recommended)
   - Never committed to version control

2. **Identity Names**: Use descriptive but not overly revealing names:
   - Good: `jane-dev`, `contractor-2024-01`
   - Avoid: `admin`, `root`, `test123`

3. **Access Scope**: This script creates users with web and API access for the dev environment. The `users` role grants access to both services via the `https-web-dial` and `https-api-dial` policies. For additional access:
   - SSH access: Use `create-identity.yml` Ansible playbook with `ssh-users` role
   - Database access: Requires identity-based policies (see [Ziti Roles and Policies](./ZITI_ROLES_AND_POLICIES.md))

## Maintenance

### Listing All Web-Only Users

To see all identities with only the `users` role:

```bash
ziti edge list identities --output-json | jq -r '.data[] | select(.roleAttributes == ["users"]) | .name'
```

### Removing a User

To remove a user identity:

```bash
ziti edge delete identity <identity-name>
```

**Note:** This will immediately revoke access. The user will need to be recreated if access is needed again.

### Updating User Access

To grant additional access (e.g., SSH), update the identity's role attributes:

```bash
ziti edge update identity <identity-name> --role-attributes "users,ssh-users"
```

## Support

For issues or questions:
1. Check this documentation
2. Review [Ziti Roles and Policies](./ZITI_ROLES_AND_POLICIES.md)
3. Check Ziti controller logs if needed
4. Contact the infrastructure team

