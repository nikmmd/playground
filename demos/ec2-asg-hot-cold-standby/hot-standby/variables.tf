variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "hot-standby-"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "ec2-hot-standby"
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
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs for cross-AZ deployment"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "instance_types" {
  description = "List of instance types for mixed instance policy"
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
  description = "List of additional IAM policy ARNs to attach to the EC2 role (e.g., S3, DynamoDB access)"
  type        = list(string)
  default     = []
}

# ============================================================================
# Hot Standby Configuration
# ============================================================================

variable "spot_for_standby" {
  description = "Use Spot instance for the standby (secondary) instance. Saves ~70% cost but may be interrupted."
  type        = bool
  default     = false
}

variable "spot_allocation_strategy" {
  description = "Spot allocation strategy when spot_for_standby=true"
  type        = string
  default     = "capacity-optimized"
}
