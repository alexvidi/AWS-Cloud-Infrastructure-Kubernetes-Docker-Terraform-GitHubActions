# -----------------------------------------------------------------------------
# VPC for the EKS cluster
# -----------------------------------------------------------------------------
# Goal:
# - Provide an isolated network with public and private subnets across 2 AZs.
# - Nodes run in private subnets; a single NAT gateway gives them outbound
#   access for image pulls and the EKS control plane.
# - Subnet tag lets Kubernetes discover where to place the external Load Balancer
#   (used by the ingress-nginx controller).
#
# Built on the well-maintained terraform-aws-modules/vpc/aws module so the
# network layer stays small and correct.
# -----------------------------------------------------------------------------

module "vpc" {
  # checkov:skip=CKV_TF_1: Pinned by version constraint from the official Terraform
  # Registry module. Commit-hash pinning is impractical for Registry sources and
  # version constraints are the standard, maintainable way to pin these modules.
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  # VPC name and IP range. All resources in the project will have IPs within 10.10.0.0/16.
  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  # Two Availability Zones for high availability. If one datacenter fails, the other keeps running.
  azs = var.azs

  # EKS nodes live in private subnets — no public IP, not reachable from the internet.
  private_subnets = ["10.10.0.0/20", "10.10.16.0/20"]

  # The Load Balancer (ingress-nginx) lives in public subnets — exposed to the internet to receive user traffic.
  public_subnets = ["10.10.128.0/20", "10.10.144.0/20"]

  # Required so EKS nodes in private subnets can reach the internet (e.g. pull images from ECR).
  # Without this, nodes have no outbound internet access.
  enable_nat_gateway = true

  # Use a single NAT Gateway to reduce cost. In production, use one per AZ for full high availability.
  single_nat_gateway = true

  # Required by EKS. Without this, nodes cannot resolve DNS names inside the VPC.
  enable_dns_hostnames = true

  # Tag consumed by the Kubernetes cloud controller to know which subnet to place the external Load Balancer in.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}
