variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "envoy-vpn-demo"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Private subnet CIDR"
  type        = string
  default     = "10.0.2.0/24"
}

variable "wireguard_port" {
  description = "WireGuard UDP port"
  type        = number
  default     = 51820
}

variable "wireguard_network" {
  description = "WireGuard tunnel network CIDR"
  type        = string
  default     = "10.8.0.0/24"
}

variable "wireguard_server_ip" {
  description = "WireGuard server tunnel IP"
  type        = string
  default     = "10.8.0.1"
}

variable "wireguard_client_ip" {
  description = "WireGuard client tunnel IP"
  type        = string
  default     = "10.8.0.2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.nano"
}

variable "postgres_db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "demodb"
}

variable "postgres_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "demouser"
}
