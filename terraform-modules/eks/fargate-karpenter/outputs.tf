################################################################################
# EKS
################################################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA certificate (base64)"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "cluster_primary_security_group_id" {
  description = "EKS cluster primary security group ID (EKS managed)"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID (module managed)"
  value       = module.eks.cluster_security_group_id
}

################################################################################
# Karpenter
################################################################################

output "karpenter_node_iam_role_arn" {
  description = "Karpenter node IAM role ARN"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_node_iam_role_name" {
  description = "Karpenter node IAM role name"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_node_security_group_id" {
  description = "Security group ID for Karpenter provisioned nodes"
  value       = aws_security_group.karpenter_node.id
}

################################################################################
# Helpers
################################################################################

output "update_kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
