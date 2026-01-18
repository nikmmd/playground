################################################################################
# PII Detection Service IAM Role (IRSA)
#
# This role is assumed by the pii-detection K8s ServiceAccount to:
# - Download EIF and binary from S3
# - Access KMS for encryption operations (attestation-gated)
################################################################################

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "pii_detection" {
  name = "${var.project_name}-pii-detection-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:enclave-demo:pii-detection"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-pii-detection-role"
  }
}

# S3 access for downloading EIF and binary
resource "aws_iam_role_policy" "pii_detection_s3" {
  name = "${var.project_name}-pii-detection-s3"
  role = aws_iam_role.pii_detection.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.eif.arn,
          "${aws_s3_bucket.eif.arn}/*"
        ]
      }
    ]
  })
}

# KMS access for encryption operations
# Note: Decrypt is restricted by key policy to attestation-verified requests
resource "aws_iam_role_policy" "pii_detection_kms" {
  name = "${var.project_name}-pii-detection-kms"
  role = aws_iam_role.pii_detection.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.enclave.arn
      }
    ]
  })
}
