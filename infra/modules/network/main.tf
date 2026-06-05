# -----------------------------------------------------------------------------
# VPC for the EKS cluster
# -----------------------------------------------------------------------------
# Goal:
# - Provide an isolated network with public and private subnets across 2 AZs.
# - Nodes run in private subnets; a single NAT gateway gives them outbound
#   access for image pulls and the EKS control plane.
# - Subnet tags let Kubernetes discover where to place external/internal load
#   balancers (used by the ingress controller Service).
#
# Built on the well-maintained terraform-aws-modules/vpc/aws module so the
# network layer stays small and correct.
# -----------------------------------------------------------------------------

locals {
  # /16 VPC split into /20 subnets: private in the first half, public offset by 8.
  private_subnets = [for k in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 4, k + 8)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Tags consumed by the in-tree AWS cloud provider to place load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
