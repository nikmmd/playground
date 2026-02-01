variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "asg_name" {
  description = "Explicit name for the ASG (allows Lambda to be created first)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for cross-AZ deployment"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "eip_allocation_id" {
  description = "Allocation ID of the EIP"
  type        = string
}

# ============================================================================
# HA Mode Configuration
# ============================================================================

variable "standby_mode" {
  description = "HA mode: 'hot' (2 running instances) or 'cold' (1 running, failover on demand)"
  type        = string
  default     = "cold"

  validation {
    condition     = contains(["hot", "cold"], var.standby_mode)
    error_message = "standby_mode must be 'hot' or 'cold'"
  }
}

# ============================================================================
# Hot Standby: Spot Configuration
# ============================================================================

variable "spot_for_standby" {
  description = <<-EOT
    Use Spot instance for the standby (secondary) instance in hot mode.
    Saves ~70% cost but may be interrupted. Only applies to hot standby mode.

    EIP behavior with spot:
    - On-demand instance is preferred for EIP (more stable)
    - EIP transfers to on-demand only when spot terminates (interruption, health failure)
    - For availability, EIP is NOT moved between running instances during rolling updates
  EOT
  type        = bool
  default     = false
}

variable "spot_allocation_strategy" {
  description = "Spot allocation strategy when spot_for_standby=true: capacity-optimized, capacity-optimized-prioritized, lowest-price, price-capacity-optimized"
  type        = string
  default     = "capacity-optimized"
}

# ============================================================================
# Cold Standby: Pre-provisioned Standby Configuration
# ============================================================================

variable "preprovisioned_standby" {
  description = "Create a pre-provisioned standby instance (stopped/hibernated) for faster failover (~30-60s vs ~2-3min). Only applies to cold standby mode. Cannot be combined with Spot."
  type        = bool
  default     = false
}

variable "preprovisioned_standby_state" {
  description = "State of pre-provisioned standby instance: 'Stopped' (boots from scratch, ~30-60s) or 'Hibernated' (resumes from RAM, ~10-20s, requires EBS encryption)"
  type        = string
  default     = "Stopped"

  validation {
    condition     = contains(["Stopped", "Hibernated"], var.preprovisioned_standby_state)
    error_message = "preprovisioned_standby_state must be 'Stopped' or 'Hibernated'"
  }
}

# ============================================================================
# Instance Configuration
# ============================================================================

variable "instance_types" {
  description = "List of instance types for mixed instance policy"
  type        = list(string)
  default     = ["t4g.nano", "t4g.micro"]
}

variable "ami_id" {
  description = "AMI ID to use. If not provided, latest AL2023 will be used"
  type        = string
  default     = null
}

variable "architecture" {
  description = "CPU architecture: x86_64 or arm64"
  type        = string
  default     = "arm64"
}

variable "user_data" {
  description = "User data script for EC2 instances"
  type        = string
  default     = ""
}

# ============================================================================
# Health Check Configuration
# ============================================================================

variable "health_check_type" {
  description = "Health check type: EC2 or ELB"
  type        = string
  default     = "EC2"
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 120
}

# ============================================================================
# IAM & Tagging
# ============================================================================

variable "resource_tag_key" {
  description = "Tag key used by EIP manager for IAM condition matching"
  type        = string
  default     = "EIPManager"
}

variable "resource_tag_value" {
  description = "Tag value used by EIP manager for IAM condition matching"
  type        = string
}

variable "additional_iam_policy_arns" {
  description = "List of additional IAM policy ARNs to attach to the EC2 role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Validation Rules
# ============================================================================

locals {
  is_hot  = var.standby_mode == "hot"
  is_cold = var.standby_mode == "cold"

  # Validate: preprovisioned_standby only in cold mode
  _validate_preprovisioned_mode = var.preprovisioned_standby && local.is_hot ? tobool("ERROR: preprovisioned_standby is only valid in cold standby mode") : true

  # Validate: spot_for_standby only in hot mode
  _validate_spot_mode = var.spot_for_standby && local.is_cold ? tobool("ERROR: spot_for_standby is only valid in hot standby mode") : true
}
