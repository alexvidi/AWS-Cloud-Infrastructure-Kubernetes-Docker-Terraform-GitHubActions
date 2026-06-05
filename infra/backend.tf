# -----------------------------------------------------------------------------
# Terraform remote backend configuration (Amazon S3)
#
# Goal:
# - Store Terraform state remotely in an S3 bucket.
# - Use native S3 state locking (use_lockfile) instead of a separate DynamoDB
#   table. This requires Terraform 1.10 or newer.
#
# The bucket below must exist before `terraform init`. See the README bootstrap
# section for the one-time creation commands.
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket       = "alexdevops99-tfstate"
    key          = "eks-fastapi/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
