# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# Phase 1: Using local state
# After running the bootstrap module, uncomment the S3 backend below and run:
#   terraform init -migrate-state
# =============================================================================

# Local state (current)
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# -----------------------------------------------------------------------------
# S3 Backend (uncomment after bootstrap)
# -----------------------------------------------------------------------------
# terraform {
#   backend "s3" {
#     bucket         = "theraprac-terraform-state"
#     key            = "phase1-vpc/terraform.tfstate"
#     region         = "us-west-2"
#     profile        = "jfinlinson_cli"
#     encrypt        = true
#     dynamodb_table = "theraprac-terraform-locks"
#   }
# }

