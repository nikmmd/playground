output "lambda_function_arn" {
  description = "ARN of the EIP manager Lambda function"
  value       = aws_lambda_function.eip_manager.arn
}

output "lambda_function_name" {
  description = "Name of the EIP manager Lambda function"
  value       = aws_lambda_function.eip_manager.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.asg_lifecycle.arn
}
