variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "appliance-"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "ec2-appliance-ha"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs for cross-AZ deployment"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "instance_types" {
  description = "List of instance types"
  type        = list(string)
  default     = ["t4g.nano", "t4g.micro"]
}

variable "architecture" {
  description = "CPU architecture: x86_64 or arm64"
  type        = string
  default     = "arm64"
}

variable "user_data" {
  description = "Custom user data script for EC2 instances"
  type        = string
  default     = ""
}

variable "resource_tag_key" {
  description = "Tag key used for IAM condition matching on managed resources"
  type        = string
  default     = "EIPManager"
}

variable "additional_iam_policy_arns" {
  description = "List of additional IAM policy ARNs to attach to the EC2 role"
  type        = list(string)
  default     = []
}

# ============================================================================
# Standby Mode Configuration
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
}

variable "cold_standby_state" {
  description = "State of cold standby: 'Stopped' (~30-60s) or 'Hibernated' (~10-20s)"
  type        = string
  default     = "Stopped"
}
