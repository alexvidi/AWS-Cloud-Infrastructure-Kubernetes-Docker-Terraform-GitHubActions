# -----------------------------------------------------------------------------
# Elastic Container Registry (ECR)
# -----------------------------------------------------------------------------
# Goal:
# - Store Docker images for the EKS cluster.
# - Scan images on push and encrypt them at rest with KMS.
# - Immutable tags: the deploy workflow pushes each image under a unique commit
#   SHA, so tags are never overwritten. This prevents tag reuse and satisfies
#   supply-chain best practice.
# - force_delete lets `terraform destroy` clean up the repo even if it still
#   holds images (useful for short-lived demo environments).
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Customer-managed KMS key for ECR encryption at rest. Created explicitly (rather
# than relying on the AWS-managed `aws/ecr` key) so Terraform guarantees the key
# exists before the repository references it, and key rotation can be enabled.
resource "aws_kms_key" "ecr" {
  description             = "Encryption key for the ${var.repository_name} ECR repository"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # Explicit key policy granting the account full administrative control (the
  # standard default policy, declared explicitly). ECR uses grants under this.
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

resource "aws_kms_alias" "ecr" {
  name          = "alias/${var.repository_name}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

# Keep the registry small: expire untagged layers so old build artifacts do not
# accumulate cost over time.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
