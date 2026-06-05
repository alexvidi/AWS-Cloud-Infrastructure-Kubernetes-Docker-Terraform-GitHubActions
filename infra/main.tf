# -----------------------------------------------------------------------------
# Core composition file:
# - Modules: network (VPC), registry (ECR), eks (EKS), github-oidc (CI role)
# - EKS access entries that grant the GitHub Actions role cluster-admin
# -----------------------------------------------------------------------------

# Two Availability Zones are enough for a demo-sized, highly-available cluster.
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# MODULES
# -----------------------------------------------------------------------------

module "network" {
  source       = "./modules/network"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "registry" {
  source          = "./modules/registry"
  repository_name = var.image_name
}

module "eks" {
  source       = "./modules/eks"
  project_name = var.project_name

  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  public_access_cidrs = var.cluster_public_access_cidrs

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

module "github_oidc" {
  source       = "./modules/github-oidc"
  project_name = var.project_name

  github_repository    = var.github_repository
  create_oidc_provider = var.create_github_oidc_provider
  ecr_repository_arn   = module.registry.repository_arn
  eks_cluster_arn      = module.eks.cluster_arn
}

# -----------------------------------------------------------------------------
# ACCESS ENTRIES
#
# The GitHub Actions role needs cluster-admin to apply manifests, create
# Secrets, install ingress-nginx, and run post-deploy smoke tests. On EKS this
# is done with native Access Entries instead of the legacy aws-auth ConfigMap.
#
# Image pulls do not need a role assignment here: the managed node group's IAM
# role carries AmazonEC2ContainerRegistryReadOnly (configured in the eks module).
# -----------------------------------------------------------------------------

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.github_oidc.role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.github_oidc.role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}
