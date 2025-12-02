# =============================================================================
# TheraPrac Infrastructure - Phase 4: Ziti Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "jfinlinson_admin"
}

variable "environment" {
  description = "Environment name (nonprod, prod)"
  type        = string
  default     = "nonprod"
}

variable "domain_name" {
  description = "Domain name for Ziti controller"
  type        = string
  default     = "ziti-nonprod.theraprac.com"
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name"
  type        = string
  default     = "theraprac.com"
}

variable "instance_type" {
  description = "EC2 instance type for Ziti"
  type        = string
  default     = "t4g.micro"
}

variable "ziti_version" {
  description = "OpenZiti version to install"
  type        = string
  default     = "1.1.3"
}

variable "github_repo" {
  description = "GitHub repository URL for infrastructure code"
  type        = string
  default     = "https://github.com/JoeFinlinson/theraprac-infra.git"
}

variable "github_branch" {
  description = "Git branch to use for Ansible playbooks"
  type        = string
  default     = "main"
}

variable "ansible_dir" {
  description = "Path to Ansible playbook directory within repo"
  type        = string
  default     = "ansible/ziti-nonprod"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.20.0.0/16"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "TheraPrac"
    ManagedBy = "Terraform"
    Phase     = "4-ziti"
  }
}

