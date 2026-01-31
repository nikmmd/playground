data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2" {
  name_prefix        = "${var.name_prefix}ec2-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = var.tags
}

# SSM Session Manager access (no SSH keys needed)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Additional IAM policies (e.g., S3, DynamoDB, etc.)
resource "aws_iam_role_policy_attachment" "additional" {
  for_each   = toset(var.additional_iam_policy_arns)
  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${var.name_prefix}ec2-"
  role        = aws_iam_role.ec2.name

  tags = var.tags
}
