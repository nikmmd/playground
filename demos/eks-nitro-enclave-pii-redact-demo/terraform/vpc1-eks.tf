data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

################################################################################
# VPC1 - EKS VPC
################################################################################

module "vpc1" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-eks-vpc"
  cidr = var.vpc1_cidr

  azs             = local.azs
  public_subnets  = var.vpc1_public_subnets
  private_subnets = var.vpc1_private_subnets
  intra_subnets   = var.vpc1_intra_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/role/elb"                              = 1
    "kubernetes.io/cluster/${var.project_name}-eks"   = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                     = 1
    "kubernetes.io/cluster/${var.project_name}-eks"   = "shared"
  }

  tags = {
    Environment = "demo"
  }
}

################################################################################
# DMZ Subnets (No Internet, VPC Endpoints Only)
################################################################################

resource "aws_subnet" "vpc1_dmz" {
  count = length(var.vpc1_dmz_subnets)

  vpc_id            = module.vpc1.vpc_id
  cidr_block        = var.vpc1_dmz_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                                                  = "${var.project_name}-eks-vpc-dmz-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"                     = 1
    "kubernetes.io/cluster/${var.project_name}-eks"   = "shared"
    Tier                                                  = "dmz"
  }
}

resource "aws_route_table" "vpc1_dmz" {
  vpc_id = module.vpc1.vpc_id

  tags = {
    Name = "${var.project_name}-eks-vpc-dmz-rt"
  }
}

resource "aws_route_table_association" "vpc1_dmz" {
  count = length(aws_subnet.vpc1_dmz)

  subnet_id      = aws_subnet.vpc1_dmz[count.index].id
  route_table_id = aws_route_table.vpc1_dmz.id
}

################################################################################
# VPC Endpoints (Gateway only - Interface endpoints not needed with NAT)
################################################################################

# S3 Gateway Endpoint (free) - for all private route tables
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc1.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc1.private_route_table_ids

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}
