################################################################################
# ENIConfig for Custom Pod Networking
# Creates ENIConfig per subnet/AZ when custom networking is enabled
################################################################################

locals {
  custom_networking_enabled = try(var.vpc_cni_custom_networking.enabled, false)
  pod_subnet_ids            = try(var.vpc_cni_custom_networking.pod_subnet_ids, [])
  pod_security_group_ids    = try(var.vpc_cni_custom_networking.pod_security_group_ids, [])
}

data "aws_subnet" "pod_subnets" {
  for_each = toset(local.pod_subnet_ids)
  id       = each.value
}

resource "kubectl_manifest" "eniconfig" {
  for_each = toset(local.pod_subnet_ids)

  yaml_body = <<-YAML
    apiVersion: crd.k8s.amazonaws.com/v1alpha1
    kind: ENIConfig
    metadata:
      name: ${data.aws_subnet.pod_subnets[each.value].availability_zone}
    spec:
      subnet: ${each.value}
      securityGroups: ${jsonencode(
        length(local.pod_security_group_ids) > 0
          ? local.pod_security_group_ids
          : [module.eks.cluster_primary_security_group_id]
      )}
  YAML

  depends_on = [module.eks]
}
