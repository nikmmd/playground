variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "eip_allocation_id" {
  description = "Allocation ID of the EIP to manage"
  type        = string
}

variable "asg_name" {
  description = "Name of the ASG to monitor"
  type        = string
}

variable "asg_arn" {
  description = "ARN of the ASG to monitor (for scoped IAM permissions)"
  type        = string
}

variable "resource_tag_key" {
  description = "Tag key used to identify managed resources for IAM condition"
  type        = string
  default     = "EIPManager"
}

variable "resource_tag_value" {
  description = "Tag value used to identify managed resources for IAM condition"
  type        = string
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
