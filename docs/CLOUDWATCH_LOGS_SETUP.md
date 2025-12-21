# CloudWatch Logs Setup & Testing

## Overview

This document describes the complete setup for CloudWatch Logs integration, including automated testing and verification.

## What Was Built

### 1. Application Code (`theraprac-api`)
- ✅ CloudWatch Logs integration via direct AWS SDK calls (no agent required)
- ✅ Automatic environment and instance ID metadata in logs
- ✅ Batched log sending (every 5 seconds or 1000 events)
- ✅ Graceful fallback if CloudWatch unavailable

### 2. Infrastructure (`theraprac-infra`)
- ✅ Terraform resources for CloudWatch log groups with retention policies
- ✅ Ansible tasks to configure SSM parameters and journald retention
- ✅ IAM permissions for CloudWatch Logs access

### 3. Testing & Verification
- ✅ Automated test scripts to verify configuration
- ✅ Deployment verification scripts
- ✅ Complete setup and test script

## Quick Start

### 1. Test Configuration (No Deployment Required)

```bash
cd theraprac-infra
./scripts/setup-and-test-logs.sh dev
```

This validates:
- Terraform configuration
- Ansible configuration  
- CloudWatch log groups (if they exist)
- SSM parameters (if set)

### 2. Create CloudWatch Log Groups

```bash
cd infra/phase3-iam
terraform plan -var="environment=dev"
terraform apply -var="environment=dev"
```

This creates:
- `/theraprac/dev/api` (1 day retention)
- `/theraprac/dev/web` (1 day retention)
- `/theraprac/test/api` (1 day retention)
- `/theraprac/test/web` (1 day retention)
- `/theraprac/prod/api` (30 day retention)
- `/theraprac/prod/web` (30 day retention)

### 3. Deploy Application

```bash
cd ansible/basic-server
ansible-playbook deploy-api.yml \
  -i inventory/dev \
  -e "target_env=dev version=latest"
```

This automatically:
- Sets SSM parameter `/theraprac/api/dev/cloudwatch-log-group`
- Configures journald retention (1 day, 500MB max)
- Deploys application with CloudWatch logging enabled

### 4. Verify Logs Are Working

```bash
cd theraprac-infra
./scripts/verify-deployment-logs.sh dev
```

This checks:
- Recent logs exist in CloudWatch
- Logs contain environment and instance_id metadata
- Retention policy is correct

## Test Scripts

### `test-cloudwatch-logs.sh`
Tests infrastructure configuration:
- CloudWatch log groups exist with correct retention
- SSM parameters are set
- IAM permissions allow log writing

**Usage:**
```bash
./scripts/test-cloudwatch-logs.sh [dev|test|prod]
```

### `verify-deployment-logs.sh`
Verifies logs are actually being sent:
- Checks for recent log streams
- Validates log content has metadata
- Confirms retention policy

**Usage:**
```bash
./scripts/verify-deployment-logs.sh [dev|test|prod]
```

### `setup-and-test-logs.sh`
Complete validation suite:
- Validates Terraform config
- Validates Ansible config
- Runs infrastructure tests

**Usage:**
```bash
./scripts/setup-and-test-logs.sh [dev|test|prod]
```

## Log Retention

| Environment | CloudWatch Retention | Journald Retention |
|------------|----------------------|-------------------|
| dev        | 1 day (24 hours)     | 1 day (24 hours)  |
| test       | 1 day (24 hours)     | 1 day (24 hours)  |
| prod       | 30 days              | 1 day (24 hours)  |

**Note:** Retention is automatic - no daily maintenance required!

## Viewing Logs

### CloudWatch Console
```
https://console.aws.amazon.com/cloudwatch/home?region=us-west-2#logsV2:log-groups/log-group/%2Ftheraprac%2Fdev%2Fapi
```

### AWS CLI
```bash
# Tail logs
aws logs tail /theraprac/dev/api --follow --region us-west-2

# Search logs
aws logs filter-log-events \
  --log-group-name /theraprac/dev/api \
  --filter-pattern "ERROR" \
  --region us-west-2
```

### CloudWatch Logs Insights
```sql
fields @timestamp, @message, environment, instance_id
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

## Troubleshooting

### Logs Not Appearing in CloudWatch

1. **Check SSM parameter:**
   ```bash
   aws ssm get-parameter \
     --name /theraprac/api/dev/cloudwatch-log-group \
     --region us-west-2
   ```

2. **Check IAM permissions:**
   ```bash
   aws iam get-instance-profile \
     --instance-profile-name <profile-name> \
     --region us-west-2
   ```

3. **Check application logs:**
   ```bash
   journalctl -u theraprac-api -f
   ```

4. **Verify log group exists:**
   ```bash
   aws logs describe-log-groups \
     --log-group-name-prefix /theraprac/dev/api \
     --region us-west-2
   ```

### Logs Missing Metadata

- Ensure `APP_ENVIRONMENT` is set in environment
- Instance ID is auto-detected from EC2 metadata (only works on EC2)

### High CloudWatch Costs

- Check retention policies are set correctly
- Verify old logs are being deleted (check log group age)
- Review log volume (may need to adjust log level)

## Cost Optimization

- **Dev/Test:** 1 day retention minimizes storage costs
- **Batching:** Logs are batched (reduces API calls)
- **Auto-cleanup:** Old logs automatically deleted
- **Journald limits:** 500MB max prevents disk fill

## Next Steps

1. ✅ Code built and validated
2. ✅ Infrastructure configured
3. ✅ Test scripts created
4. ⏭️ Apply Terraform to create log groups
5. ⏭️ Deploy application
6. ⏭️ Verify logs are working

All scripts are ready to use - just run them with the appropriate environment!





