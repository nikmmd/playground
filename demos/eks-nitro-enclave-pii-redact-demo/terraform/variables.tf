variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "eks-nitro-enclave-demo"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# VPC1 - EKS VPC
variable "vpc1_cidr" {
  description = "VPC1 (EKS) CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc1_public_subnets" {
  description = "VPC1 public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "vpc1_private_subnets" {
  description = "VPC1 private subnet CIDRs (EKS regular nodes)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "vpc1_intra_subnets" {
  description = "VPC1 intra subnet CIDRs (no NAT)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

variable "vpc1_dmz_subnets" {
  description = "VPC1 DMZ subnet CIDRs (Nitro Enclave nodes, no internet, VPC endpoints)"
  type        = list(string)
  default     = ["10.0.31.0/24", "10.0.32.0/24", "10.0.33.0/24"]
}

# VPC2 - PostgreSQL VPC
variable "vpc2_cidr" {
  description = "VPC2 (PostgreSQL) CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "vpc2_public_subnets" {
  description = "VPC2 public subnet CIDRs"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

variable "vpc2_private_subnets" {
  description = "VPC2 private subnet CIDRs"
  type        = list(string)
  default     = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]
}

variable "vpc2_intra_subnets" {
  description = "VPC2 intra subnet CIDRs (PostgreSQL EC2)"
  type        = list(string)
  default     = ["10.1.21.0/24", "10.1.22.0/24", "10.1.23.0/24"]
}

# EKS Configuration
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.34"
}

variable "nitro_instance_type" {
  description = "Instance type for Nitro Enclave nodes (must be enclave-enabled)"
  type        = string
  default     = "m6a.xlarge"
}

# PostgreSQL Configuration
variable "postgres_instance_type" {
  description = "EC2 instance type for PostgreSQL"
  type        = string
  default     = "t4g.nano"
}

variable "postgres_db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "eventsdb"
}

variable "postgres_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "enclaveuser"
}
