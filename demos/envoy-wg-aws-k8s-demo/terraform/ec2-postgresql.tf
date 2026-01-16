module "postgresql_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name = "postgresql-server"

  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.postgresql_sg.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  user_data = base64encode(templatefile("${path.module}/../scripts/postgresql-setup.sh", {
    project_name      = var.project_name
    aws_region        = var.aws_region
    postgres_username = var.postgres_username
    postgres_db_name  = var.postgres_db_name
  }))

  depends_on = [
    aws_ssm_parameter.postgres_password,
    aws_route.private_nat
  ]

  user_data_replace_on_change = true
}
