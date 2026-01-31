locals {
  # Capacity settings based on mode
  min_size         = local.is_hot ? 2 : 1
  desired_capacity = local.is_hot ? 2 : 1
  max_size         = local.is_hot ? 2 : (var.preprovisioned_standby ? 2 : 1)

  # Alarm threshold matches desired capacity
  alarm_threshold = local.is_hot ? 2 : 1

  # Instance refresh settings
  min_healthy_percentage = local.is_hot ? 50 : 0

  # Spot configuration (derived from spot_for_standby)
  # - Hot + spot_for_standby=true: 1 on-demand (primary) + 1 spot (standby)
  # - Hot + spot_for_standby=false: 2 on-demand
  # - Cold: always on-demand (1 instance or preprovisioned standby which requires on-demand)
  on_demand_base_capacity         = local.is_hot && var.spot_for_standby ? 1 : 100
  on_demand_percentage_above_base = local.is_hot && var.spot_for_standby ? 0 : 100
  use_spot                        = local.is_hot && var.spot_for_standby

  # Pre-provisioned standby (warm pool) only in cold mode
  use_preprovisioned_standby = local.is_cold && var.preprovisioned_standby
}

resource "aws_autoscaling_group" "this" {
  name                = var.asg_name
  vpc_zone_identifier = var.subnet_ids
  min_size            = local.min_size
  max_size            = local.max_size
  desired_capacity    = local.desired_capacity

  # Use latest version of launch template
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.this.id
        version            = aws_launch_template.this.latest_version
      }

      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type = override.value
        }
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = local.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = local.on_demand_percentage_above_base
      spot_allocation_strategy                 = local.use_spot ? var.spot_allocation_strategy : null
    }
  }

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # Force delete to avoid destroy getting stuck on lifecycle hooks or warm pool
  force_delete              = true
  wait_for_capacity_timeout = "0"

  # Pre-provisioned standby (AWS warm pool) for faster cold standby failover
  dynamic "warm_pool" {
    for_each = local.use_preprovisioned_standby ? [1] : []
    content {
      pool_state = var.preprovisioned_standby_state
      min_size   = 1

      instance_reuse_policy {
        reuse_on_scale_in = true
      }
    }
  }

  # Terminate oldest instance first
  termination_policies = ["OldestInstance"]

  # Enable instance refresh for rolling updates
  # Note: launch_template changes automatically trigger refresh
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = local.min_healthy_percentage
    }
  }

  # Launch lifecycle hook for EIP association
  initial_lifecycle_hook {
    name                 = "${var.name_prefix}launch-hook"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 300
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
  }

  # Termination lifecycle hook for EIP failover
  initial_lifecycle_hook {
    name                 = "${var.name_prefix}terminate-hook"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 300
    lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}asg"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch alarm for ASG health
resource "aws_cloudwatch_metric_alarm" "unhealthy_instances" {
  alarm_name          = "${var.name_prefix}unhealthy-instances"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = local.alarm_threshold
  alarm_description   = "Alert when less than ${local.alarm_threshold} instance(s) are healthy"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  tags = var.tags
}
