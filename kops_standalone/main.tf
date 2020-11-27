# public zone
provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

locals {
  kops_sub = format("k8s.%s", var.zone)
}

resource "aws_route53_zone" "main" {
  name = format("%s",var.zone)
}

resource "aws_route53_zone" "k8s" {
  name = local.kops_sub

  tags = {
    Environment = "dev"
  }
}

resource "aws_route53_record" "k8s_ns" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.kops_sub
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.k8s.name_servers
}

# private s3 bucket to store configs    
resource "aws_s3_bucket" "kops_bucket" {
 bucket = format("k8s-state-%s", var.zone)
  acl    = "private"
  tags = {
    Name        = "K8s Bucket"
    Environment = "Dev"
  }
}

# kops doesn't support custom keys atm
# https://github.com/kubernetes/kops/issues/4728
# resource "tls_private_key" "this" {
#   algorithm = "RSA"
# }

# module "key_pair" {
#   source = "terraform-aws-modules/key-pair/aws"
#   key_name   = "ssh_key"
#   public_key = tls_private_key.this.public_key_openssh
# }

output "kops-bucket" {
  value = aws_s3_bucket.kops_bucket.bucket
}

output "kops-domain" {
  value = local.kops_sub
}

output "kops-zone" {
  value = aws_route53_record.k8s_ns.zone_id
}

# output "kops-public-key" {
#   value = tls_private_key.this.public_key_openssh
#   sensitive = true
# }