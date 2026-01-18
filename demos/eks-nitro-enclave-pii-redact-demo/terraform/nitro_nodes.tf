################################################################################
# Nitro Enclave Nodes - IAM
################################################################################

resource "aws_iam_role" "nitro_node" {
  name = "${var.project_name}-nitro-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-nitro-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "nitro_node_eks_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nitro_node.name
}

resource "aws_iam_role_policy_attachment" "nitro_node_ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nitro_node.name
}

resource "aws_iam_role_policy_attachment" "nitro_node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nitro_node.name
}

resource "aws_iam_role_policy_attachment" "nitro_node_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.nitro_node.name
}

resource "aws_iam_role_policy" "nitro_node_ssm_sendcommand" {
  name = "${var.project_name}-nitro-ssm-sendcommand"
  role = aws_iam_role.nitro_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession",
          "ssm:DescribeSessions"
        ]
        Resource = "*"
      }
    ]
  })
}

# KMS permissions for enclave attestation
# Note: The key policy restricts Decrypt to attestation-verified requests only
resource "aws_iam_role_policy" "nitro_node_kms" {
  name = "${var.project_name}-nitro-kms"
  role = aws_iam_role.nitro_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.enclave.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nitro_node" {
  name = "${var.project_name}-nitro-node-profile"
  role = aws_iam_role.nitro_node.name
}

################################################################################
# Nitro Enclave Nodes - Security Group
################################################################################

resource "aws_security_group" "nitro_nodes" {
  name_prefix = "${var.project_name}-nitro-"
  description = "Security group for Nitro Enclave nodes"
  vpc_id      = module.vpc1.vpc_id

  ingress {
    description     = "Allow from EKS cluster"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [module.eks.cluster_security_group_id]
  }

  ingress {
    description = "Allow from VPC1"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc1_cidr]
  }

  egress {
    description = "Allow all outbound to VPC1"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc1_cidr]
  }

  egress {
    description = "Allow PostgreSQL to VPC2"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.vpc2_intra_subnets
  }

  egress {
    description = "Allow HTTPS (for VPC endpoints)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nitro-nodes-sg"
  }
}

################################################################################
# Nitro Enclave Nodes - EKS Access Entry
################################################################################

resource "aws_eks_access_entry" "nitro_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.nitro_node.arn
  type          = "EC2_LINUX"

  depends_on = [module.eks]
}

################################################################################
# Nitro Enclave Nodes - Launch Template
#
# EKS Auto Mode does not support userData or custom AMIs.
# For Nitro Enclaves, we need a managed node group with a launch template
# that configures hugepages, allocator service, and nitro-cli.
################################################################################

# Get EKS optimized AL2023 AMI
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.eks_cluster_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

resource "aws_launch_template" "nitro_enclave" {
  name_prefix   = "${var.project_name}-nitro-"
  image_id      = data.aws_ssm_parameter.eks_ami.value
  instance_type = var.nitro_instance_type

  # Enable Nitro Enclaves on the instance
  enclave_options {
    enabled = true
  }

  # NOTE: Do NOT specify iam_instance_profile here.
  # EKS managed node groups create their own instance profile from node_role_arn.

  # Security groups
  vpc_security_group_ids = [
    aws_security_group.nitro_nodes.id,
    module.eks.node_security_group_id
  ]

  # EBS root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Metadata options (IMDSv2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # User data: Shell script (pre-nodeadm) + NodeConfig for EKS bootstrap
  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

# Install Nitro Enclaves CLI and dependencies
dnf install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel jq

# Configure Nitro Enclaves allocator
# The allocator service automatically manages hugepages based on memory_mib
mkdir -p /etc/nitro_enclaves
cat > /etc/nitro_enclaves/allocator.yaml <<ALLOCATOR
---
memory_mib: 7168
cpu_count: 2
ALLOCATOR

# Add users to 'ne' group for enclave access
usermod -aG ne ec2-user || true
usermod -aG ne root || true

# Enable and start the Nitro Enclaves allocator service
# This will allocate hugepages automatically
systemctl enable nitro-enclaves-allocator.service
systemctl start nitro-enclaves-allocator.service

echo "Nitro Enclave setup complete"

--BOUNDARY
Content-Type: application/node.eks.aws

apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${module.eks.cluster_name}
    apiServerEndpoint: ${module.eks.cluster_endpoint}
    certificateAuthority: ${module.eks.cluster_certificate_authority_data}
    cidr: ${module.eks.cluster_service_cidr}

--BOUNDARY--
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                               = "${var.project_name}-nitro-node"
      "node.kubernetes.io/nitro-enclave" = "true"
    }
  }

  tags = {
    Name = "${var.project_name}-nitro-launch-template"
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Nitro Enclave Nodes - Managed Node Group
################################################################################

resource "aws_eks_node_group" "nitro_enclave_node" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${var.project_name}-nitro_node"
  node_role_arn   = aws_iam_role.nitro_node.arn

  # If we can use spot
  capacity_type = "SPOT"

  # use private subnets (have nat gateway for package installation)
  subnet_ids = module.vpc1.private_subnets

  # scaling configuration
  scaling_config {
    desired_size = 1
    min_size     = 0
    max_size     = 3
  }

  # use launch template with nitro enclave configuration
  launch_template {
    id      = aws_launch_template.nitro_enclave.id
    version = aws_launch_template.nitro_enclave.latest_version
  }

  # labels for node selection
  labels = {
    "node.kubernetes.io/nitro-enclave" = "true"
    "aws-nitro-enclaves-k8s-dp"        = "enabled"
  }

  # taint to ensure only enclave workloads schedule here
  taint {
    key    = "nitro-enclave"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  # update config
  update_config {
    max_unavailable = 1
  }

  tags = {
    name        = "${var.project_name}-nitro-node-group"
    environment = "demo"
  }

  depends_on = [
    aws_iam_role_policy_attachment.nitro_node_eks_worker,
    aws_iam_role_policy_attachment.nitro_node_ecr_readonly,
    aws_iam_role_policy_attachment.nitro_node_cni,
    aws_eks_access_entry.nitro_nodes,
  ]
}
