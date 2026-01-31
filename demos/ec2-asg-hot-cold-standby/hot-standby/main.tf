locals {
  prefix   = var.name_prefix
  asg_name = "${var.name_prefix}asg"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.prefix}vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Auto-assign public IP for immediate internet access (SSM, updates)
  # EIP replaces it and AWS auto-releases the temporary IP (no extra cost)
  map_public_ip_on_launch = true

  public_subnet_tags = {
    Type = "public"
  }

  private_subnet_tags = {
    Type = "private"
  }

  tags = local.common_tags
}

# Security Group
resource "aws_security_group" "ec2" {
  name_prefix = "${local.prefix}ec2-"
  description = "Security group for EC2 instances"
  vpc_id      = module.vpc.vpc_id

  # No SSH - use SSM Session Manager instead:
  # aws ssm start-session --target <instance-id>

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefix}ec2-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EIP for hot standby
resource "aws_eip" "this" {
  domain = "vpc"
  tags = {
    Name                   = "${local.prefix}eip"
    (var.resource_tag_key) = local.prefix
  }
}

# Lambda EIP Manager - CREATED FIRST (before ASG launches instances)
module "eip_manager" {
  source = "../../../terraform-modules/ec2-appliance-ha/eip-manager"

  name_prefix       = local.prefix
  eip_allocation_id = aws_eip.this.allocation_id
  asg_name          = local.asg_name
  asg_arn           = "arn:aws:autoscaling:${var.aws_region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"
  deployment_mode   = "hot-standby"

  resource_tag_key   = var.resource_tag_key
  resource_tag_value = local.prefix

  tags = local.common_tags
}

# HA ASG Module (Hot Standby) - CREATED AFTER Lambda/EventBridge ready
module "asg_ha" {
  source = "../../../terraform-modules/ec2-appliance-ha/asg"

  # ── Required ────────────────────────────────────────────────────────────────
  name_prefix        = local.prefix
  asg_name           = local.asg_name
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [aws_security_group.ec2.id]
  eip_allocation_id  = aws_eip.this.allocation_id

  # ── HA Mode ─────────────────────────────────────────────────────────────────
  # "cold" = 1 running instance, failover on demand
  # "hot"  = 2 running instances, instant failover
  standby_mode = "hot"

  # ── Hot Standby Options ─────────────────────────────────────────────────────
  # Use Spot for the secondary instance (saves ~70%, but may be interrupted)
  spot_for_standby         = var.spot_for_standby
  spot_allocation_strategy = var.spot_allocation_strategy

  # ── Instance Configuration ──────────────────────────────────────────────────
  instance_types = var.instance_types
  architecture   = var.architecture
  user_data      = var.user_data

  # ── IAM & Security ──────────────────────────────────────────────────────────
  resource_tag_key           = var.resource_tag_key
  resource_tag_value         = local.prefix
  additional_iam_policy_arns = var.additional_iam_policy_arns

  # ── Tags ────────────────────────────────────────────────────────────────────
  tags = local.common_tags

  # Ensure Lambda and EventBridge are ready before ASG launches instances
  depends_on = [module.eip_manager]
}

data "aws_caller_identity" "current" {}
