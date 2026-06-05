# -----------------------------------------------------------------------------
# Elastic Container Registry (ECR)
# -----------------------------------------------------------------------------
# Goal:
# - Store Docker images for the EKS cluster.
# - Scan images on push and encrypt them at rest.
# - force_delete lets `terraform destroy` clean up the repo even if it still
#   holds images (useful for short-lived demo environments).
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
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
