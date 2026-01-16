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

module "wireguard_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name = "wireguard-server"

  ami                         = data.aws_ami.al2023_arm64.id
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [module.wireguard_sg.security_group_id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  source_dest_check           = false

  user_data = base64encode(templatefile("${path.module}/../scripts/wireguard-server-setup.sh", {
    project_name        = var.project_name
    aws_region          = var.aws_region
    server_ip           = var.wireguard_server_ip
    client_ip           = var.wireguard_client_ip
    wireguard_port      = var.wireguard_port
    private_subnet_cidr = var.private_subnet_cidr
  }))

  depends_on = [
    aws_ssm_parameter.wg_server_private_key,
    aws_ssm_parameter.wg_client_public_key,
    aws_ssm_parameter.wg_preshared_key
  ]

  user_data_replace_on_change = true
}

resource "aws_eip" "wireguard" {
  instance = module.wireguard_server.id
  domain   = "vpc"
}

# Route private subnet traffic through WireGuard server (NAT instance)
resource "aws_route" "private_nat" {
  route_table_id         = module.vpc.private_route_table_ids[0]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.wireguard_server.primary_network_interface_id
}
