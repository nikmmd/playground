# ============================================================================
# Auto Scaling Group with Optional Warm Pool
# ============================================================================
#
# Modes:
#   - none: Single instance, ASG replaces on failure (~2-3 min)
#   - cold: Warm pool with Stopped/Hibernated standby (~30-60s / ~10-20s)
#   - hot:  Warm pool with Running standby (instant failover)
#
# Instance refresh ensures zero-downtime during patching/upgrades by pulling
# from warm pool before terminating the active instance.
# ============================================================================

resource "aws_autoscaling_group" "this" {
  name                = var.asg_name
  vpc_zone_identifier = var.subnet_ids
  min_size            = 1
  max_size            = local.use_warm_pool || var.rolling_update ? 2 : 1
  desired_capacity    = 1

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

    # All on-demand (no spot in simplified version)
    instances_distribution {
      on_demand_base_capacity                  = 100
      on_demand_percentage_above_base_capacity = 100
    }
  }

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period

  # Force delete to avoid destroy getting stuck on lifecycle hooks or warm pool
  force_delete              = true
  wait_for_capacity_timeout = "0"

  # Warm pool for hot/cold standby modes
  dynamic "warm_pool" {
    for_each = local.use_warm_pool ? [1] : []
    content {
      pool_state                  = local.warm_pool_state
      min_size                    = 1
      max_group_prepared_capacity = 2

      instance_reuse_policy {
        reuse_on_scale_in = true
      }
    }
  }

  # Terminate oldest instance first (ensures fresh instances after refresh)
  termination_policies = ["OldestInstance"]

  # Instance refresh for zero-downtime patching/upgrades
  # With warm pool: pulls standby first, then terminates old instance
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage       = var.min_healthy_percentage
      instance_warmup              = var.health_check_grace_period
      skip_matching                = true
      auto_rollback                = true
      scale_in_protected_instances = "Wait"
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

  # Tags
  tag {
    key                 = "Name"
    value               = "${var.name_prefix}instance"
    propagate_at_launch = true
  }

  tag {
    key                 = var.resource_tag_key
    value               = var.resource_tag_value
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

# ============================================================================
# CloudWatch Alarm for Unhealthy Instances (Optional)
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "unhealthy_instances" {
  count = var.unhealthy_alarm_enabled ? 1 : 0

  alarm_name          = "${var.name_prefix}unhealthy-instances"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when no healthy instances are available"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this.name
  }

  tags = var.tags
}
