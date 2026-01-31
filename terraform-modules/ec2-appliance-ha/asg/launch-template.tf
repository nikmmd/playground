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

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.al2023.id

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

  # Enable hibernation for warm pool with Hibernated state
  # Requires EBS root volume encryption
  dynamic "hibernation_options" {
    for_each = var.preprovisioned_standby && var.preprovisioned_standby_state == "Hibernated" ? [1] : []
    content {
      configured = true
    }
  }

  # EBS root volume - encrypted for hibernation support
  dynamic "block_device_mappings" {
    for_each = var.preprovisioned_standby && var.preprovisioned_standby_state == "Hibernated" ? [1] : []
    content {
      device_name = data.aws_ami.al2023.root_device_name
      ebs {
        volume_size           = 20
        volume_type           = "gp3"
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  user_data = base64encode(var.user_data != "" ? var.user_data : local.default_user_data)

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name                       = "${var.name_prefix}instance"
      (var.resource_tag_key)     = var.resource_tag_value
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
      Name                       = "${var.name_prefix}eni"
      (var.resource_tag_key)     = var.resource_tag_value
    })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}
