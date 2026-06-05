# -----------------------------------------------------------------------------
# Terraform provider configuration for AWS
# -----------------------------------------------------------------------------
# This project uses the official AWS provider. The region is driven by the
# `region` variable so the same configuration can target different AWS regions.
# -----------------------------------------------------------------------------

terraform {
  # use_lockfile (native S3 state locking) requires Terraform 1.10+.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}
