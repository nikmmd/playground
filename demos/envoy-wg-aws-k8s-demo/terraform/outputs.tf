output "wireguard_public_ip" {
  description = "WireGuard server public IP"
  value       = aws_eip.wireguard.public_ip
}

output "wireguard_private_ip" {
  description = "WireGuard server private IP"
  value       = module.wireguard_server.private_ip
}

output "postgresql_private_ip" {
  description = "PostgreSQL server private IP"
  value       = module.postgresql_server.private_ip
}

output "wg_server_public_key" {
  description = "WireGuard server public key"
  value       = wireguard_asymmetric_key.server.public_key
  sensitive   = true
}

output "wg_client_private_key" {
  description = "WireGuard client private key"
  value       = wireguard_asymmetric_key.client.private_key
  sensitive   = true
}

output "wg_client_public_key" {
  description = "WireGuard client public key"
  value       = wireguard_asymmetric_key.client.public_key
  sensitive   = true
}

output "wg_preshared_key" {
  description = "WireGuard preshared key"
  value       = wireguard_preshared_key.psk.key
  sensitive   = true
}

output "postgres_password" {
  description = "PostgreSQL password"
  value       = random_password.postgres.result
  sensitive   = true
}

output "ssm_postgres_password_path" {
  description = "SSM parameter path for PostgreSQL password"
  value       = aws_ssm_parameter.postgres_password.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "wireguard_instance_id" {
  description = "WireGuard EC2 instance ID"
  value       = module.wireguard_server.id
}

output "postgresql_instance_id" {
  description = "PostgreSQL EC2 instance ID"
  value       = module.postgresql_server.id
}
