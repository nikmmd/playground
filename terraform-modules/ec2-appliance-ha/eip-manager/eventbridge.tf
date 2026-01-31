resource "aws_cloudwatch_event_rule" "asg_lifecycle" {
  name_prefix = "${var.name_prefix}asg-lifecycle-"
  description = "Capture ASG lifecycle events for EIP management"

  event_pattern = jsonencode({
    source = ["aws.autoscaling"]
    detail-type = [
      # Note: AWS uses lowercase 'launch' and 'terminate' in event detail-type
      "EC2 Instance-launch Lifecycle Action",
      "EC2 Instance-terminate Lifecycle Action"
    ]
    detail = {
      AutoScalingGroupName = [var.asg_name]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.asg_lifecycle.name
  target_id = "${var.name_prefix}eip-manager"
  arn       = aws_lambda_function.eip_manager.arn
}

# NOTE: EC2 state-change rule removed intentionally.
# ASG lifecycle hooks handle ALL terminations including:
# - Manual termination (console/CLI/API)
# - Spot interruptions
# - Health check failures
# - Scale-in events
# The EC2 state-change rule was over-permissive (triggered for ALL EC2 in account)
# and caused race conditions with lifecycle hooks.
