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
  description = <<-EOT
    Standby mode for failover:
    - 'none': No standby, ASG replaces failed instance (~2-3 min failover)
    - 'cold': Stopped standby in warm pool (~30-60s failover)
    - 'hot':  Running standby in warm pool (instant failover)
  EOT
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "cold", "hot"], var.standby_mode)
    error_message = "standby_mode must be 'none', 'cold', or 'hot'"
  }
}

variable "cold_standby_state" {
  description = "State of cold standby: 'Stopped' (~30-60s) or 'Hibernated' (~10-20s, requires EBS encryption)"
  type        = string
  default     = "Stopped"

  validation {
    condition     = contains(["Stopped", "Hibernated"], var.cold_standby_state)
    error_message = "cold_standby_state must be 'Stopped' or 'Hibernated'"
  }
}

variable "rolling_update" {
  description = "Enable zero-downtime rolling updates by allowing a temporary extra instance during refresh. When false, accepts brief downtime during patching. Only applies to standby_mode='none'; cold/hot modes always have zero-downtime via warm pool."
  type        = bool
  default     = true
}

variable "min_healthy_percentage" {
  description = "Minimum percentage of healthy instances during instance refresh (0-100). Set to 100 for zero-downtime, 0 to allow all instances to be replaced at once."
  type        = number
  default     = 100
}

# ============================================================================
# Instance Configuration
# ============================================================================

variable "instance_types" {
  description = "List of instance types (first available will be used)"
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

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 20
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

variable "unhealthy_alarm_enabled" {
  description = "Enable CloudWatch alarm for unhealthy instances"
  type        = bool
  default     = true
}

# ============================================================================
# Derived Locals
# ============================================================================

locals {
  use_warm_pool = var.standby_mode != "none"

  # Warm pool state: Running for hot, Stopped/Hibernated for cold
  warm_pool_state = var.standby_mode == "hot" ? "Running" : var.cold_standby_state
}
