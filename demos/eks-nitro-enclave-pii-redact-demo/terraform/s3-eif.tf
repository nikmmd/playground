################################################################################
# S3 Bucket for Enclave Image File (EIF) Storage
################################################################################

resource "random_id" "eif_bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "eif" {
  bucket        = "${var.project_name}-eif-${random_id.eif_bucket.hex}"
  force_destroy = true
  tags = {
    Name = "${var.project_name}-eif-bucket"
  }
}

resource "aws_s3_bucket_versioning" "eif" {
  bucket = aws_s3_bucket.eif.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "eif" {
  bucket = aws_s3_bucket.eif.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "eif" {
  bucket = aws_s3_bucket.eif.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# IAM Policy for EIF S3 Access
################################################################################

# Policy for Nitro nodes to download EIF
resource "aws_iam_role_policy" "nitro_node_s3_eif" {
  name = "${var.project_name}-nitro-s3-eif"
  role = aws_iam_role.nitro_node.id

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

# Note: PII Detection pod S3 access is defined in pii-detection-iam.tf
