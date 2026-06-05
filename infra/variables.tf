# -----------------------------------------------------------------------------
# Input variables for the Terraform project
# -----------------------------------------------------------------------------

# Base name used as prefix for all AWS resources.
variable "project_name" {
  description = "Base name used as prefix for all AWS resources."
  type        = string
  default     = "alexdevops99"
}

# AWS region where the resources will be created.
variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

# Container image / ECR repository name.
variable "image_name" {
  description = "Name of the application image and its ECR repository."
  type        = string
  default     = "market-quote-api"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.10.0.0/16"
}

# -----------------------------------------------------------------------------
# EKS cluster
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes control plane version for EKS."
  type        = string
  default     = "1.31"
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API server endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group."
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC
# -----------------------------------------------------------------------------

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, in owner/repo form."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions IAM OIDC provider. Set to false if it already exists in the account."
  type        = bool
  default     = true
}
