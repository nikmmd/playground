################################################################################
# PostgreSQL EC2 Instance
################################################################################

data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

################################################################################
# IAM Role for PostgreSQL EC2 (SSM access)
################################################################################

resource "aws_iam_role" "postgresql" {
  name = "${var.project_name}-postgresql-role"

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
    Name = "${var.project_name}-postgresql-role"
  }
}

resource "aws_iam_role_policy_attachment" "postgresql_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.postgresql.name
}

resource "aws_iam_role_policy" "postgresql_ssm_parameters" {
  name = "${var.project_name}-postgresql-ssm-params"
  role = aws_iam_role.postgresql.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "postgresql" {
  name = "${var.project_name}-postgresql-profile"
  role = aws_iam_role.postgresql.name
}

################################################################################
# PostgreSQL Password in SSM
################################################################################

resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "postgres_password" {
  name        = "/${var.project_name}/postgres/password"
  description = "PostgreSQL password for ${var.postgres_username}"
  type        = "SecureString"
  value       = random_password.postgres.result

  tags = {
    Name = "${var.project_name}-postgres-password"
  }
}

################################################################################
# Security Group for PostgreSQL
################################################################################

resource "aws_security_group" "postgresql" {
  name_prefix = "${var.project_name}-postgresql-"
  description = "Security group for PostgreSQL EC2"
  vpc_id      = module.vpc2.vpc_id

  # Allow PostgreSQL from VPC1 DMZ (via peering)
  ingress {
    description = "PostgreSQL from VPC1 DMZ"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.vpc1_dmz_subnets
  }

  # Allow PostgreSQL from VPC1 private (via peering)
  ingress {
    description = "PostgreSQL from VPC1 private"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.vpc1_private_subnets
  }

  # Allow HTTPS for SSM and package repos
  egress {
    description = "HTTPS for SSM and package repos"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP for package repos (some mirrors use HTTP)
  egress {
    description = "HTTP for package repos"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow responses back to VPC1
  egress {
    description = "Responses to VPC1"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc1_cidr]
  }

  egress {
    description = "Responses to VPC2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc2_cidr]
  }


  tags = {
    Name = "${var.project_name}-postgresql-sg"
  }
}

################################################################################
# PostgreSQL EC2 Instance
################################################################################

module "postgresql" {
  source               = "terraform-aws-modules/ec2-instance/aws"
  version              = "~> 6.0"
  create_spot_instance = true

  name = "${var.project_name}-postgresql"

  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.postgres_instance_type
  subnet_id              = module.vpc2.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.postgresql.id]
  iam_instance_profile   = aws_iam_instance_profile.postgresql.name

  user_data_base64 = base64encode(templatefile("${path.module}/../scripts/ec2-userdata/postgresql-setup.sh", {
    project_name      = var.project_name
    aws_region        = var.aws_region
    postgres_username = var.postgres_username
    postgres_db_name  = var.postgres_db_name
    vpc1_cidr         = var.vpc1_cidr
    vpc2_cidr         = var.vpc2_cidr
  }))

  user_data_replace_on_change = true

  # Create secure output directory
  root_block_device = {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }


  depends_on = [
    aws_ssm_parameter.postgres_password
  ]

  tags = {
    Name = "${var.project_name}-postgresql"
  }
}
