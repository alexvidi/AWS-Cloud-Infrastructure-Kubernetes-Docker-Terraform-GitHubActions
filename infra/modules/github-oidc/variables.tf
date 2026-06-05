variable "project_name" {
  description = "Base name used as prefix for IAM resources."
  type        = string
}

variable "github_repository" {
  description = "Repository allowed to assume the role, in owner/repo form."
  type        = string
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider, or reuse an existing one."
  type        = bool
  default     = true
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the role may push to."
  type        = string
}

variable "eks_cluster_arn" {
  description = "ARN of the EKS cluster the role may describe."
  type        = string
}
