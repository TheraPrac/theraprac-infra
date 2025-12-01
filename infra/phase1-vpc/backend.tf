# =============================================================================
# Terraform Backend Configuration - S3 Remote State
# =============================================================================
# Note: Uses default credential chain (AWS_PROFILE env var or SSO session)
# Run: export AWS_PROFILE=jfinlinson_cli before terraform commands
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "theraprac-tfstate-32fcc26f"
    key            = "phase1-vpc/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "theraprac-terraform-locks"
  }
}
