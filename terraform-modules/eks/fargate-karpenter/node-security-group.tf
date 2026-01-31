################################################################################
# Karpenter Node Security Group
################################################################################

locals {
  default_node_security_group_rules = {
    ingress_self_all = {
      description = "Node to node all traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_cluster_to_nodes = {
      description                   = "Cluster API to nodes"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    egress_all = {
      description = "Allow all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  node_security_group_rules = merge(local.default_node_security_group_rules, var.node_security_group_additional_rules)
}

resource "aws_security_group" "karpenter_node" {
  name_prefix = "${var.cluster_name}-karpenter-node-"
  description = "Security group for Karpenter provisioned nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name                     = "${var.cluster_name}-karpenter-node"
    "karpenter.sh/discovery" = var.cluster_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "karpenter_node" {
  for_each = local.node_security_group_rules

  security_group_id = aws_security_group.karpenter_node.id
  type              = each.value.type
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  description       = try(each.value.description, null)

  cidr_blocks              = try(each.value.cidr_blocks, null)
  ipv6_cidr_blocks         = try(each.value.ipv6_cidr_blocks, null)
  prefix_list_ids          = try(each.value.prefix_list_ids, null)
  self                     = try(each.value.self, null)
  source_security_group_id = try(each.value.source_cluster_security_group, false) ? module.eks.cluster_primary_security_group_id : try(each.value.source_security_group_id, null)
}
