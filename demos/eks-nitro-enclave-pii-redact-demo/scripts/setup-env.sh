#!/bin/bash
set -euo pipefail

# Generate k8s/.env from terraform/tofu outputs
# Usage: ./scripts/setup-env.sh
#        TF=terraform ./scripts/setup-env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
K8S_DIR="$PROJECT_DIR/k8s"

# Use tofu by default, override with TF=terraform
TF="${TF:-tofu}"

cd "$TERRAFORM_DIR"

echo "Fetching outputs using $TF..."

cat > "$K8S_DIR/.env" <<EOF
# Generated from $TF outputs - $(date)
# Re-run ./scripts/setup-env.sh to regenerate

# IAM & KMS
PII_DETECTION_ROLE_ARN=$($TF output -raw pii_detection_role_arn)
KMS_KEY_ARN=$($TF output -raw enclave_kms_key_arn)
EIF_BUCKET=$($TF output -raw eif_bucket_name)

# Karpenter NodeClass
NITRO_NODE_ROLE_NAME=$($TF output -raw nitro_node_role_name)
NITRO_NODE_SG_ID=$($TF output -raw nitro_node_sg_id)
EKS_NODE_SG_ID=$($TF output -raw eks_node_sg_id)
PROJECT_NAME=$($TF output -raw eks_cluster_name | sed 's/-eks$//')

# PostgreSQL
POSTGRES_HOST=$($TF output -raw postgresql_private_ip)
POSTGRES_PORT=5432
POSTGRES_DATABASE=$($TF output -raw postgres_db_name)
POSTGRES_USER=$($TF output -raw postgres_username)
POSTGRES_PASSWORD=$($TF output -raw postgres_password)
EOF

echo "Generated: $K8S_DIR/.env"
echo ""
echo "Update kubeconfig:"
echo "  $($TF output -raw eks_update_kubeconfig_command)"
