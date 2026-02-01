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

variable "deployment_mode" {
  description = "Deployment mode: hot-standby or cold-standby"
  type        = string
  validation {
    condition     = contains(["hot-standby", "cold-standby"], var.deployment_mode)
    error_message = "deployment_mode must be 'hot-standby' or 'cold-standby'"
  }
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

variable "prefer_on_demand" {
  description = <<-EOT
    Prefer on-demand instances for EIP association in hot-standby mode with mixed spot/on-demand.

    When true:
    - Initial EIP assignment prefers on-demand over spot instances
    - EIP transfers to on-demand when spot instance terminates (interruption, health failure)

    Note: For availability, EIP is NOT moved between running instances. The transfer only
    occurs when the current EIP holder terminates, ensuring zero-downtime during rolling updates.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
