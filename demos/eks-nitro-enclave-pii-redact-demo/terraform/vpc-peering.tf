################################################################################
# VPC Peering Connection
################################################################################

resource "aws_vpc_peering_connection" "vpc1_to_vpc2" {
  vpc_id      = module.vpc1.vpc_id
  peer_vpc_id = module.vpc2.vpc_id
  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = {
    Name = "${var.project_name}-vpc1-to-vpc2-peering"
  }
}

################################################################################
# Routes from VPC1 DMZ to VPC2
################################################################################

# Route from VPC1 DMZ subnet to VPC2 CIDR
resource "aws_route" "vpc1_dmz_to_vpc2" {
  route_table_id            = aws_route_table.vpc1_dmz.id
  destination_cidr_block    = var.vpc2_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc1_to_vpc2.id
}

# Also add route from VPC1 private subnets to VPC2 (for general EKS access)
resource "aws_route" "vpc1_private_to_vpc2" {
  count = length(module.vpc1.private_route_table_ids)

  route_table_id            = module.vpc1.private_route_table_ids[count.index]
  destination_cidr_block    = var.vpc2_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc1_to_vpc2.id
}

################################################################################
# Routes from VPC2 to VPC1
################################################################################

# Route from VPC2 private subnets to VPC1 CIDR (PostgreSQL responses back to pods)
resource "aws_route" "vpc2_private_to_vpc1" {
  count = length(module.vpc2.private_route_table_ids)

  route_table_id            = module.vpc2.private_route_table_ids[count.index]
  destination_cidr_block    = var.vpc1_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc1_to_vpc2.id
}

# Route from VPC2 intra subnets to VPC1 CIDR (legacy, can be removed if not using intra)
resource "aws_route" "vpc2_intra_to_vpc1" {
  count = length(module.vpc2.intra_route_table_ids)

  route_table_id            = module.vpc2.intra_route_table_ids[count.index]
  destination_cidr_block    = var.vpc1_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc1_to_vpc2.id
}
