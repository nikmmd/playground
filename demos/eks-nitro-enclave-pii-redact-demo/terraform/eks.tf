################################################################################
# EKS Cluster with Automode
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.14.0"

  name               = "${var.project_name}-eks"
  kubernetes_version = var.eks_cluster_version

  # Public endpoint for simplicity
  endpoint_public_access  = true
  endpoint_private_access = true

  # Enable cluster creator admin permissions
  enable_cluster_creator_admin_permissions = true

  # EKS Addons (needed for managed node groups outside Auto Mode)
  # Automode issue
  addons = {
    #CoreDns issues on automode? 2026/1/18
    # coredns = {
    #   most_recent = true
    # }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
  }

  vpc_id     = module.vpc1.vpc_id
  subnet_ids = concat(module.vpc1.private_subnets, aws_subnet.vpc1_dmz[*].id)

  # Control plane subnets (for ENIs)
  control_plane_subnet_ids = module.vpc1.intra_subnets

  # IAM role names (avoid prefix length issues)
  iam_role_use_name_prefix      = false
  iam_role_name                 = "${var.project_name}-cluster-role"
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.project_name}-node-role"

  # Enable EKS Automode for managed node provisioning
  # https://docs.aws.amazon.com/eks/latest/userguide/set-builtin-node-pools.html
  compute_config = {
    enabled    = false #TODO: disable for now
    node_pools = []
    # node_pools = ["general-purpose", "system"]
  }

  # Security group rules for cluster
  security_group_additional_rules = {
    ingress_vpc2_postgresql = {
      description = "Allow ingress from VPC2 PostgreSQL"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [var.vpc2_cidr]
    }
  }

  # Node security group rules (for automode managed nodes)
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  tags = {
    Environment = "demo"
  }
}
