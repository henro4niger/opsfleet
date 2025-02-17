data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# let's tag the subnets appropriately for EKS
resource "aws_ec2_tag" "private_subnet_cluster_tags" {
  for_each    = toset(var.private_subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "private_subnet_karpenter_tags" {
  for_each    = toset(var.private_subnet_ids)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.33"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  enable_irsa         = true
  authentication_mode = "API_AND_CONFIG_MAP"

  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    initial = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      subnet_ids     = var.private_subnet_ids
    }
  }

  tags = {
    Environment = "demo"
    Terraform   = "true"
  }
}