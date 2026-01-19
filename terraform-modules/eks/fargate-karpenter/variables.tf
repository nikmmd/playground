################################################################################
# Required
################################################################################

variable "cluster_name" {
  description = "Name for the EKS cluster and related resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes"
  type        = list(string)
}

################################################################################
# Optional
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.1.1"
}

variable "control_plane_subnet_ids" {
  description = "Subnet IDs for EKS control plane ENIs (defaults to private_subnet_ids)"
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_enabled_log_types" {
  description = "List of control plane log types to enable (api, audit, authenticator, controllerManager, scheduler)"
  type        = list(string)
  default     = []
}

variable "cluster_deletion_protection" {
  description = "Enable deletion protection for the cluster"
  type        = bool
  default     = true
}

variable "cluster_ip_family" {
  description = "IP family for the cluster (ipv4, ipv6)"
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.cluster_ip_family)
    error_message = "cluster_ip_family must be ipv4 or ipv6"
  }
}

################################################################################
# VPC CNI Configuration
################################################################################

variable "vpc_cni_prefix_delegation" {
  description = "Enable VPC CNI prefix delegation for faster pod IP allocation"
  type = object({
    enabled            = optional(bool, true)
    warm_prefix_target = optional(number, 1)
  })
  default = {
    enabled            = true
    warm_prefix_target = 1
  }
}

variable "vpc_cni_custom_networking" {
  description = "Custom networking with dedicated pod subnets"
  type = object({
    enabled                = bool
    pod_subnet_ids         = list(string)
    pod_security_group_ids = optional(list(string), [])
  })
  default = null
}

################################################################################
# Merge overrides
################################################################################

variable "cluster_addons" {
  description = "Additional cluster addons to merge with defaults"
  type        = any
  default     = {}
}

variable "access_entries" {
  description = "Additional access entries to merge with defaults"
  type        = any
  default     = {}
}

variable "fargate_profiles" {
  description = "Additional Fargate profiles to merge with defaults"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Additional tags to merge with defaults"
  type        = map(string)
  default     = {}
}

variable "kms_key_administrators" {
  description = "Additional KMS key administrator ARNs to merge with defaults"
  type        = list(string)
  default     = []
}

variable "node_security_group_additional_rules" {
  description = "Additional security group rules to merge with defaults for Karpenter nodes"
  type        = any
  default     = {}
}

variable "cluster_security_group_additional_rules" {
  description = "Additional security group rules for cluster control plane access"
  type        = any
  default     = {}
}
