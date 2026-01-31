output "eip_public_ip" {
  description = "Public IP of the EIP (use this to access the service)"
  value       = aws_eip.this.public_ip
}

output "eip_allocation_id" {
  description = "Allocation ID of the EIP"
  value       = aws_eip.this.allocation_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "security_group_id" {
  description = "EC2 security group ID"
  value       = aws_security_group.ec2.id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.asg_ha.asg_name
}

output "standby_mode" {
  description = "HA standby mode"
  value       = module.asg_ha.standby_mode
}

output "preprovisioned_standby" {
  description = "Whether pre-provisioned standby is enabled"
  value       = module.asg_ha.preprovisioned_standby
}

output "lambda_function_name" {
  description = "EIP manager Lambda function name"
  value       = module.eip_manager.lambda_function_name
}
