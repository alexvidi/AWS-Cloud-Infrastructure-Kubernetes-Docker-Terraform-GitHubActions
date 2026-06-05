# -----------------------------------------------------------------------------
# Amazon EKS cluster
# -----------------------------------------------------------------------------
# Goal:
# - Managed Kubernetes control plane with a private managed node group.
# - VPC CNI with NetworkPolicy enforcement enabled so the application
#   NetworkPolicy is actually honored (the AKS version used Cilium for this).
# - Control plane logs shipped to CloudWatch (mirrors the Azure Log Analytics
#   intent) with a short retention to keep demo cost low.
# - Node IAM role carries ECR read-only so pods can pull images without IRSA.
#
# Built on the terraform-aws-modules/eks/aws module.
# -----------------------------------------------------------------------------

module "eks" {
  # checkov:skip=CKV_TF_1: Pinned by version constraint from the official Terraform
  # Registry module. Commit-hash pinning is impractical for Registry sources and
  # version constraints are the standard, maintainable way to pin these modules.
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-eks"
  cluster_version = var.kubernetes_version

  # Public API endpoint, optionally restricted to known CIDRs.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # The identity that runs `terraform apply` becomes a cluster admin so it can
  # bootstrap the cluster (the GitHub Actions role is added separately).
  enable_cluster_creator_admin_permissions = true

  # Ship control plane logs to CloudWatch with a short retention window.
  cluster_enabled_log_types              = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      # Configure the CNI before the nodes join so networking is ready, and
      # turn on NetworkPolicy enforcement in the AWS VPC CNI.
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size

      # Allow pods to pull from ECR using the node role (no IRSA needed).
      iam_role_additional_policies = {
        ecr_read = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }
}
