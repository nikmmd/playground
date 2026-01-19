################################################################################
# Defaults
################################################################################

locals {
  cluster_name = var.cluster_name

  default_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  # VPC CNI config - prefix delegation (IPv4 only) + optional custom networking
  vpc_cni_env = merge(
    # Prefix delegation for IPv4 clusters (IPv6 uses automatic /80 prefixes)
    var.vpc_cni_prefix_delegation.enabled && var.cluster_ip_family == "ipv4" ? {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = tostring(var.vpc_cni_prefix_delegation.warm_prefix_target)
    } : {},
    # Custom networking (optional)
    var.vpc_cni_custom_networking != null && var.vpc_cni_custom_networking.enabled ? {
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
      ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
    } : {}
  )

  default_cluster_addons = {
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni = {
      before_compute       = true
      configuration_values = length(local.vpc_cni_env) > 0 ? jsonencode({ env = local.vpc_cni_env }) : null
    }
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
  }

  default_fargate_profiles = {
    kube-system = {
      selectors = [{ namespace = "kube-system" }]
    }
    karpenter = {
      selectors = [{ namespace = "karpenter" }]
    }
  }

  #TODO: Harcode ci user
  default_access_entries = {}

  default_kms_key_administrators = []

  # Merged values
  tags                   = merge(local.default_tags, var.tags)
  cluster_addons         = merge(local.default_cluster_addons, var.cluster_addons)
  fargate_profiles       = merge(local.default_fargate_profiles, var.fargate_profiles)
  access_entries         = merge(local.default_access_entries, var.access_entries)
  kms_key_administrators = distinct(concat(local.default_kms_key_administrators, var.kms_key_administrators))
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.14.0"

  authentication_mode = "API"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access

  cluster_enabled_log_types = var.cluster_enabled_log_types

  cluster_deletion_protection              = var.cluster_deletion_protection
  cluster_ip_family                        = var.cluster_ip_family
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = length(var.control_plane_subnet_ids) > 0 ? var.control_plane_subnet_ids : var.private_subnet_ids

  # Fargate uses cluster primary security group, additional SG for custom rules
  create_cluster_security_group                         = true
  create_node_security_group                            = false
  cluster_security_group_additional_rules               = var.cluster_security_group_additional_rules
  cluster_security_group_use_name_prefix                = true
  cluster_security_group_name                           = "${local.cluster_name}-cluster"

  # Merged configs
  cluster_addons   = local.cluster_addons
  fargate_profiles = local.fargate_profiles
  access_entries   = local.access_entries

  # IAM
  iam_role_use_name_prefix = false
  iam_role_name            = "${var.cluster_name}-cluster-role"

  # KMS
  kms_key_administrators = local.kms_key_administrators

  tags = local.tags
}
