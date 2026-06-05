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

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  # KMS encryption with the AWS-managed `aws/ecr` key: stronger than AES256 and
  # incurs no extra key cost (no customer-managed key created).
  encryption_configuration {
    encryption_type = "KMS"
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
