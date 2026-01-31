terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/eip_manager.py"
  output_path = "${path.module}/.terraform/lambda/eip_manager.zip"
}

resource "aws_lambda_function" "eip_manager" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${var.name_prefix}eip-manager"
  role             = aws_iam_role.lambda.arn
  handler          = "eip_manager.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128

  # Note: reserved_concurrent_executions = 1 would prevent race conditions,
  # but requires sufficient account concurrency quota. With only ASG lifecycle
  # events (no EC2 state-change rule), race conditions are unlikely.
  # The Lambda code uses AllowReassociation=True which handles concurrent calls gracefully.

  environment {
    variables = {
      EIP_ALLOCATION_ID = var.eip_allocation_id
      DEPLOYMENT_MODE   = var.deployment_mode
      ASG_NAME          = var.asg_name
      PREFER_ON_DEMAND  = tostring(var.prefer_on_demand)
    }
  }

  tags = var.tags
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.eip_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_lifecycle.arn
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.eip_manager.function_name}"
  retention_in_days = 14

  tags = var.tags
}
