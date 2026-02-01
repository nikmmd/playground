output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.this.latest_version
}

output "instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.arn
}

output "iam_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2.arn
}

output "standby_mode" {
  description = "Standby mode: none, cold, or hot"
  value       = var.standby_mode
}

output "warm_pool_enabled" {
  description = "Whether warm pool is enabled (cold or hot mode)"
  value       = local.use_warm_pool
}

output "warm_pool_state" {
  description = "State of instances in warm pool (Running, Stopped, or Hibernated)"
  value       = local.use_warm_pool ? local.warm_pool_state : null
}
