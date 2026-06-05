# -----------------------------------------------------------------------------
# Terraform outputs
# -----------------------------------------------------------------------------
# These values are printed after "terraform apply" and feed the CI/CD secrets
# and local kubectl configuration.
# -----------------------------------------------------------------------------

output "region" {
  description = "AWS region the stack is deployed in."
  value       = var.region
}

output "ecr_repository_url" {
  description = "ECR repository URL for the application image."
  value       = module.registry.repository_url
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "github_actions_role_arn" {
  description = "IAM role ARN that GitHub Actions assumes via OIDC."
  value       = module.github_oidc.role_arn
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = module.network.vpc_id
}

output "configure_kubectl" {
  description = "Command to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
