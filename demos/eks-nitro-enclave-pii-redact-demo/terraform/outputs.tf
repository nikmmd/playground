################################################################################
# VPC Outputs
################################################################################

output "vpc1_id" {
  description = "VPC1 (EKS) ID"
  value       = module.vpc1.vpc_id
}

output "vpc1_private_subnets" {
  description = "VPC1 private subnet IDs"
  value       = module.vpc1.private_subnets
}

output "vpc1_dmz_subnets" {
  description = "VPC1 DMZ subnet IDs"
  value       = aws_subnet.vpc1_dmz[*].id
}

output "vpc2_id" {
  description = "VPC2 (PostgreSQL) ID"
  value       = module.vpc2.vpc_id
}

output "vpc2_intra_subnets" {
  description = "VPC2 intra subnet IDs"
  value       = module.vpc2.intra_subnets
}

output "vpc_peering_id" {
  description = "VPC Peering connection ID"
  value       = aws_vpc_peering_connection.vpc1_to_vpc2.id
}

################################################################################
# EKS Outputs
################################################################################

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_oidc_issuer_url" {
  description = "EKS OIDC issuer URL"
  value       = module.eks.cluster_oidc_issuer_url
}

output "eks_update_kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

################################################################################
# Nitro Node Outputs (EKS Managed Node Group)
################################################################################

output "nitro_node_role_arn" {
  description = "Nitro node IAM role ARN"
  value       = aws_iam_role.nitro_node.arn
}

output "nitro_node_role_name" {
  description = "Nitro node IAM role name"
  value       = aws_iam_role.nitro_node.name
}

output "nitro_node_group_name" {
  description = "Nitro enclave EKS node group name"
  value       = aws_eks_node_group.nitro_enclave_node.node_group_name
}

output "nitro_node_sg_id" {
  description = "Nitro node security group ID"
  value       = aws_security_group.nitro_nodes.id
}

output "eks_node_sg_id" {
  description = "EKS managed node security group ID"
  value       = module.eks.node_security_group_id
}

################################################################################
# PostgreSQL Outputs
################################################################################

output "postgresql_instance_id" {
  description = "PostgreSQL EC2 instance ID"
  value       = module.postgresql.id
}

output "postgresql_private_ip" {
  description = "PostgreSQL EC2 private IP"
  value       = module.postgresql.private_ip
}

output "postgres_db_name" {
  description = "PostgreSQL database name"
  value       = var.postgres_db_name
}

output "postgres_username" {
  description = "PostgreSQL username"
  value       = var.postgres_username
}

output "postgres_password" {
  description = "PostgreSQL password"
  value       = random_password.postgres.result
  sensitive   = true
}

output "postgresql_ssm_connect_command" {
  description = "Command to connect to PostgreSQL EC2 via SSM"
  value       = "aws ssm start-session --target ${module.postgresql.id} --region ${var.aws_region}"
}

################################################################################
# PII Detection Outputs
################################################################################

output "pii_detection_role_arn" {
  description = "PII Detection pod IAM role ARN"
  value       = aws_iam_role.pii_detection.arn
}

################################################################################
# EIF Storage Outputs
################################################################################

output "eif_bucket_name" {
  description = "S3 bucket name for EIF storage"
  value       = aws_s3_bucket.eif.bucket
}

output "eif_bucket_arn" {
  description = "S3 bucket ARN for EIF storage"
  value       = aws_s3_bucket.eif.arn
}

################################################################################
# Quick Start Commands
################################################################################

output "quick_start" {
  description = "Quick start commands"
  value       = <<-EOT

    ============================================================
    Confidential PII Detection with Nitro Enclaves - Quick Start
    ============================================================

    # 1. Update kubeconfig
    aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}

    # 2. Wait for Nitro nodes to join (may take 5-10 minutes)
    kubectl get nodes -l node.kubernetes.io/nitro-enclave=true

    # 3. Build artifacts on a Nitro-capable instance:

    # Build enclave EIF
    cd enclave
    docker build -t pii-detection-enclave .
    nitro-cli build-enclave --docker-uri pii-detection-enclave --output-file pii-detection.eif

    # Note the PCR0 value!
    nitro-cli describe-eif --eif-path pii-detection.eif

    # Build parent app (Go binary)
    cd ../parent-app
    GOOS=linux GOARCH=amd64 GOAMD64=v1 CGO_ENABLED=0 go build -o pii-detection-parent .

    # Upload to S3
    aws s3 cp pii-detection.eif s3://${aws_s3_bucket.eif.bucket}/pii-detection.eif
    aws s3 cp pii-detection-parent s3://${aws_s3_bucket.eif.bucket}/pii-detection-parent

    # 4. Update KMS key with PCR0:
    echo 'enclave_pcr0 = "<your-pcr0>"' >> terraform.tfvars
    terraform apply

    # 5. Generate K8s secrets and apply manifests
    cd scripts && ./generate-k8s-secrets.sh

    # 6. Deploy the PII Detection service
    kubectl apply -k k8s/

    # 7. Test the service
    kubectl port-forward svc/pii-detection 8080:80 -n enclave-demo
    curl http://localhost:8080/health
    curl -X POST http://localhost:8080/seed -d '{"count": 10}'
    curl http://localhost:8080/documents
    curl -X POST http://localhost:8080/documents/1/redact

    ============================================================
    EIF Bucket: ${aws_s3_bucket.eif.bucket}
    PostgreSQL Instance: ${module.postgresql.id}
    ============================================================

  EOT
}
