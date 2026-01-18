################################################################################
# KMS Key for Nitro Enclave Attestation
#
# This key can ONLY be used by the verified Nitro Enclave.
# The key policy uses attestation conditions to ensure only an enclave
# with the correct PCR values (code hash) can decrypt data.
################################################################################

################################################################################
# Auto-read PCR0 from S3 object metadata via AWS CLI
# Falls back to var.enclave_pcr0 if EIF doesn't exist yet
################################################################################

data "external" "eif_pcr0" {
  program = ["bash", "-c", <<-EOF
    PCR0=$(aws s3api head-object \
      --bucket "${aws_s3_bucket.eif.id}" \
      --key "pii-detection.eif" \
      --query "Metadata.pcr0" \
      --output text 2>/dev/null || echo "")

    if [ -z "$PCR0" ] || [ "$PCR0" = "None" ] || [ "$PCR0" = "null" ]; then
      PCR0="${var.enclave_pcr0}"
    fi

    echo "{\"pcr0\": \"$PCR0\"}"
  EOF
  ]
}

locals {
  pcr0_value = data.external.eif_pcr0.result.pcr0
}

################################################################################

resource "aws_kms_key" "enclave" {
  description             = "${var.project_name} - Enclave attestation-protected key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # Policy allows:
  # 1. Account root for key administration
  # 2. Enclave role for Decrypt - BUT only with valid attestation
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Key administrators
      {
        Sid    = "KeyAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      # Allow encrypt from anywhere (clients encrypt data to send to enclave)
      {
        Sid    = "AllowEncrypt"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      # CRITICAL: Only allow decrypt from Nitro Enclave with valid attestation
      # Uses the pii-detection IRSA role (not the node role) since credentials
      # are passed from the parent app which uses the pod's service account
      {
        Sid    = "AllowEnclaveDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.pii_detection.arn
        }
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          # Require attestation document
          StringEqualsIgnoreCase = {
            # PCR0: Hash of the enclave image (EIF)
            # This ensures only our specific enclave code can decrypt
            # PCR0 is auto-read from S3 object metadata (set during upload)
            "kms:RecipientAttestation:PCR0" = local.pcr0_value
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-enclave-key"
  }
}

resource "aws_kms_alias" "enclave" {
  name          = "alias/${var.project_name}-enclave"
  target_key_id = aws_kms_key.enclave.key_id
}

################################################################################
# Variables
################################################################################

variable "enclave_pcr0" {
  description = "PCR0 value (enclave image hash) for KMS attestation. Set to 'PLACEHOLDER' initially, update after building EIF."
  type        = string
  # Using zeros as placeholder - this allows initial deployment
  # Real PCR0 will be 48 bytes (96 hex chars) of the enclave image hash
  default = "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
}

################################################################################
# Outputs
################################################################################

output "enclave_kms_key_arn" {
  description = "KMS key ARN for enclave attestation"
  value       = aws_kms_key.enclave.arn
}

output "enclave_kms_key_alias" {
  description = "KMS key alias for enclave attestation"
  value       = aws_kms_alias.enclave.name
}

output "enclave_pcr0_used" {
  description = "PCR0 value used in KMS policy (from S3 metadata or variable)"
  value       = local.pcr0_value
}
