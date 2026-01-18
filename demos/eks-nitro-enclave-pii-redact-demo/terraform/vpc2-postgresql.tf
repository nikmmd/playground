################################################################################
# VPC2 - PostgreSQL VPC
################################################################################

module "vpc2" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-postgresql-vpc"
  cidr = var.vpc2_cidr

  azs             = local.azs
  public_subnets  = var.vpc2_public_subnets
  private_subnets = var.vpc2_private_subnets
  intra_subnets   = var.vpc2_intra_subnets

  # NAT gateway for package installation during EC2 bootstrap
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "demo"
  }
}

################################################################################
# VPC Endpoints (Gateway only - Interface endpoints not needed with NAT)
################################################################################

# S3 Gateway Endpoint for VPC2 (free)
resource "aws_vpc_endpoint" "vpc2_s3" {
  vpc_id            = module.vpc2.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc2.private_route_table_ids

  tags = {
    Name = "${var.project_name}-vpc2-s3-endpoint"
  }
}
