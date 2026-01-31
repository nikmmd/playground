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
  description = "HA standby mode: hot or cold"
  value       = var.standby_mode
}

output "preprovisioned_standby" {
  description = "Whether pre-provisioned standby is enabled"
  value       = local.use_preprovisioned_standby
}

output "spot_for_standby" {
  description = "Whether Spot is used for standby instance"
  value       = local.use_spot
}

output "desired_capacity" {
  description = "Desired number of running instances"
  value       = local.desired_capacity
}
