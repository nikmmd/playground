data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_permissions" {
  # EIP operations - scoped to tagged resources
  statement {
    sid    = "EIPAssociate"
    effect = "Allow"
    actions = [
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress"
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:elastic-ip/${var.eip_allocation_id}",
      "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:network-interface/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/${var.resource_tag_key}"
      values   = [var.resource_tag_value]
    }
  }

  # Allow EIP operations on the specific EIP (EIPs don't support tag conditions for associate/disassociate)
  statement {
    sid    = "EIPOperationsOnSpecificEIP"
    effect = "Allow"
    actions = [
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress"
    ]
    resources = [
      "arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:elastic-ip/${var.eip_allocation_id}"
    ]
  }

  # Describe operations - read-only, scoped where possible
  statement {
    sid    = "EC2DescribeOperations"
    effect = "Allow"
    actions = [
      "ec2:DescribeAddresses",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.id]
    }
  }

  # ASG operations - scoped to specific ASG
  statement {
    sid    = "ASGDescribeOperations"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances"
    ]
    resources = ["*"]
  }

  # ASG lifecycle operations - scoped to specific ASG ARN
  statement {
    sid    = "ASGLifecycleOperations"
    effect = "Allow"
    actions = [
      "autoscaling:CompleteLifecycleAction",
      "autoscaling:RecordLifecycleActionHeartbeat"
    ]
    resources = [var.asg_arn]
  }
}

resource "aws_iam_role" "lambda" {
  name_prefix        = "${var.name_prefix}eip-manager-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = var.tags
}

# Use AWS managed policy for basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for EC2/ASG operations with conditions
resource "aws_iam_role_policy" "lambda" {
  name_prefix = "${var.name_prefix}eip-manager-"
  role        = aws_iam_role.lambda.id
  policy      = data.aws_iam_policy_document.lambda_permissions.json
}
