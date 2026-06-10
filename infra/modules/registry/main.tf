# -----------------------------------------------------------------------------
# Elastic Container Registry (ECR)
# -----------------------------------------------------------------------------
# Goal:
# - Store Docker images for the EKS cluster.
# - Encrypt images at rest using a customer-managed KMS key.
# - Immutable tags: once an image is pushed with a commit SHA tag, it cannot
#   be overwritten. This prevents supply-chain attacks.
# - Scan images automatically on every push as a second security layer
#   (Trivy in CI is the first layer).
# -----------------------------------------------------------------------------

# Used to get the AWS account ID dynamically for the KMS key policy.
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# KMS KEY
# Customer-managed encryption key for ECR images.
# AWS encrypts ECR by default with its own key (aws/ecr), but with a
# customer-managed key you have full control — you can audit it, rotate it,
# and disable it if needed.
# -----------------------------------------------------------------------------
resource "aws_kms_key" "ecr" {
  description = "Encryption key for the ${var.repository_name} ECR repository"

  # AWS waits 7 days before permanently deleting the key after removal.
  # This prevents accidental data loss — encrypted images would be
  # unrecoverable if the key is destroyed.
  deletion_window_in_days = 7

  # AWS automatically rotates the key every year.
  # If the key is ever compromised, its validity has an expiry date.
  enable_key_rotation = true

  # Grants the AWS account full administrative control over this key.
  # This is the standard policy recommended by AWS, declared explicitly
  # so Terraform manages it.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

# Human-readable name for the KMS key.
# KMS keys have IDs like "a1b2c3d4-e5f6-..." which are hard to identify.
# The alias makes it easy to find the key in the AWS console.
resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.repository_name}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

# -----------------------------------------------------------------------------
# ECR REPOSITORY
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # Once an image is pushed with a tag (e.g. commit SHA "abc123"),
  # no one can overwrite it with a different image using the same tag.
  # Protects against supply-chain attacks where a legitimate image
  # could be replaced by a malicious one.
  image_tag_mutability = "IMMUTABLE"

  # Automatically scan every image on push against a CVE database.
  # This is a second security layer — Trivy in CI is the first.
  # Covers the case where someone pushes an image directly to ECR
  # without going through the CI pipeline.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encrypt all images using the customer-managed KMS key defined above.
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}
