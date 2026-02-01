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
  description = "Standby mode: none, cold, or hot"
  value       = module.asg_ha.standby_mode
}

output "warm_pool_enabled" {
  description = "Whether warm pool is enabled"
  value       = module.asg_ha.warm_pool_enabled
}

output "warm_pool_state" {
  description = "Warm pool instance state"
  value       = module.asg_ha.warm_pool_state
}

output "lambda_function_name" {
  description = "EIP manager Lambda function name"
  value       = module.eip_manager.lambda_function_name
}
