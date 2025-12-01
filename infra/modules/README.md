# Terraform Modules

Shared modules for TheraPrac infrastructure.

## Available Modules

### bootstrap

Creates S3 bucket and DynamoDB table for Terraform remote state.

**Usage:**

```bash
cd infra/modules/bootstrap
terraform init
terraform plan
terraform apply
```

After applying, update `backend.tf` in each phase module:

1. Comment out the `backend "local"` block
2. Uncomment the `backend "s3"` block
3. Run `terraform init -migrate-state`

**Resources Created:**

- S3 bucket with versioning and encryption
- DynamoDB table for state locking
- Public access blocks on S3 bucket

