resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "postgres_password" {
  name  = "/${var.project_name}/postgres/password"
  type  = "SecureString"
  value = random_password.postgres.result
}

resource "aws_ssm_parameter" "postgres_username" {
  name  = "/${var.project_name}/postgres/username"
  type  = "String"
  value = var.postgres_username
}

resource "aws_ssm_parameter" "postgres_dbname" {
  name  = "/${var.project_name}/postgres/dbname"
  type  = "String"
  value = var.postgres_db_name
}

# WireGuard keys in SSM
resource "aws_ssm_parameter" "wg_server_private_key" {
  name  = "/${var.project_name}/wireguard/server-private-key"
  type  = "SecureString"
  value = wireguard_asymmetric_key.server.private_key
}

resource "aws_ssm_parameter" "wg_client_public_key" {
  name  = "/${var.project_name}/wireguard/client-public-key"
  type  = "String"
  value = wireguard_asymmetric_key.client.public_key
}

resource "aws_ssm_parameter" "wg_preshared_key" {
  name  = "/${var.project_name}/wireguard/preshared-key"
  type  = "SecureString"
  value = wireguard_preshared_key.psk.key
}
