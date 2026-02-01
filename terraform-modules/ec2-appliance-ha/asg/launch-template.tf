data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  # Use standard AL2023 AMI (not minimal) - includes hibernation agent
  # Minimal AMI lacks ec2-hibinit-agent required for hibernation
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-${var.architecture}"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = [var.architecture]
  }
}

data "aws_ami" "custom" {
  count = var.ami_id != null ? 1 : 0

  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}

locals {
  # Use custom AMI if provided, otherwise use AL2023
  ami_id           = var.ami_id != null ? var.ami_id : data.aws_ami.al2023.id
  root_device_name = var.ami_id != null ? data.aws_ami.custom[0].root_device_name : data.aws_ami.al2023.root_device_name

  # Minimal user data for fast boot and clean hibernation
  # Heavy operations (updates, package installs) should be baked into AMI
  default_user_data = <<-EOF
    #!/bin/bash
    # Minimal setup - keeps boot fast and hibernation clean
    echo "$(hostname)" > /tmp/instance-id
  EOF
}

resource "aws_launch_template" "this" {
  name_prefix = "${var.name_prefix}lt-"
  image_id    = local.ami_id

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  vpc_security_group_ids = var.security_group_ids

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  # Enable hibernation for cold standby with Hibernated state
  dynamic "hibernation_options" {
    for_each = var.standby_mode == "cold" && var.cold_standby_state == "Hibernated" ? [1] : []
    content {
      configured = true
    }
  }

  # EBS root volume - always encrypted (required for hibernation, good practice otherwise)
  block_device_mappings {
    device_name = local.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(var.user_data != "" ? var.user_data : local.default_user_data)

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name                   = "${var.name_prefix}instance"
      (var.resource_tag_key) = var.resource_tag_value
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}volume"
    })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(var.tags, {
      Name                   = "${var.name_prefix}eni"
      (var.resource_tag_key) = var.resource_tag_value
    })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}
