
provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

resource "aws_instance" "demo" {
  # aws linux2
  ami           = "ami-04d29b6f966df1537"
  tags = {
    "Name" = var.name
  }
  instance_type = "t2.micro"
}

output "public_ip" {
      value = aws_instance.demo.public_ip
}