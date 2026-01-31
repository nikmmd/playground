# EC2 ASG High Availability Module

Terraform module for deploying EC2 instances with automatic EIP failover using Auto Scaling Groups.

## Features

- **Hot Standby**: 2 running instances, instant EIP failover
- **Cold Standby**: 1 running instance, EIP failover on demand
- **Pre-provisioned Standby**: Stopped instance ready for fast failover (cold mode)
- **Spot Support**: Use Spot instances for secondary instance (hot mode)
- **Cross-AZ Deployment**: Instances spread across availability zones
- **SSM Session Manager**: No SSH keys required

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Hot Standby Mode                                │
│                                                                              │
│    ┌──────────────┐         EIP          ┌──────────────┐                   │
│    │   Primary    │◄───── (moves on ─────│   Standby    │                   │
│    │  (running)   │       failover)      │  (running)   │                   │
│    │  on-demand   │                      │ on-demand/spot│                   │
│    └──────────────┘                      └──────────────┘                   │
│          AZ-a                                  AZ-b                          │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              Cold Standby Mode                               │
│                                                                              │
│    ┌──────────────┐         EIP          ┌──────────────┐                   │
│    │   Primary    │◄───── (moves on ─────│   Standby    │                   │
│    │  (running)   │       failover)      │  (stopped)   │  ← optional       │
│    │  on-demand   │                      │  on-demand   │    pre-provisioned│
│    └──────────────┘                      └──────────────┘                   │
│          AZ-a                                  AZ-b                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Configuration Options

### Standby Mode

| Mode | `standby_mode` | Running Instances | Failover Time |
|------|----------------|-------------------|---------------|
| Hot  | `"hot"`        | 2                 | Instant       |
| Cold | `"cold"`       | 1                 | 2-3 minutes   |

### Hot Standby Options

| Variable | Description | Default |
|----------|-------------|---------|
| `spot_for_standby` | Use Spot for secondary instance (~70% savings) | `false` |
| `spot_allocation_strategy` | Spot allocation strategy | `"capacity-optimized"` |

### Cold Standby Options

| Variable | Description | Default |
|----------|-------------|---------|
| `preprovisioned_standby` | Create stopped instance for faster failover | `false` |
| `preprovisioned_standby_state` | `"Stopped"` (~30-60s) or `"Hibernated"` (~10-20s) | `"Stopped"` |

## Usage Examples

### Cold Standby (Basic)

Single instance, new instance launched on failure (~2-3 min failover).

```hcl
module "asg_ha" {
  source = "path/to/ec2-asg-ha"

  name_prefix        = "my-app-"
  asg_name           = "my-app-asg"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [aws_security_group.app.id]
  eip_allocation_id  = aws_eip.app.allocation_id

  standby_mode = "cold"

  instance_types     = ["t4g.nano", "t4g.micro"]
  architecture       = "arm64"
  resource_tag_key   = "EIPManager"
  resource_tag_value = "my-app"
}
```

### Cold Standby (Pre-provisioned)

Single running instance + stopped instance ready to start (~30-60s failover).

```hcl
module "asg_ha" {
  source = "path/to/ec2-asg-ha"

  # ... required variables ...

  standby_mode             = "cold"
  preprovisioned_standby   = true
  preprovisioned_standby_state = "Stopped"  # or "Hibernated" for ~10-20s
}
```

### Hot Standby (All On-Demand)

Two running instances, instant failover, maximum reliability.

```hcl
module "asg_ha" {
  source = "path/to/ec2-asg-ha"

  # ... required variables ...

  standby_mode = "hot"
}
```

### Hot Standby (Primary On-Demand + Secondary Spot)

Two running instances, instant failover, ~35% cost savings.

```hcl
module "asg_ha" {
  source = "path/to/ec2-asg-ha"

  # ... required variables ...

  standby_mode             = "hot"
  spot_for_standby         = true
  spot_allocation_strategy = "capacity-optimized"
}
```

## Cost Comparison

| Configuration | Monthly Cost (t4g.nano) | Failover Time |
|---------------|-------------------------|---------------|
| Cold (basic) | ~$3 | 2-3 min |
| Cold (pre-provisioned) | ~$3 + EBS | 30-60s |
| Hot (all on-demand) | ~$6 | Instant |
| Hot (spot secondary) | ~$4.50 | Instant |

*Costs are approximate and vary by region. Does not include EIP costs.*

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name_prefix` | Prefix for resource names | `string` | - | yes |
| `asg_name` | Explicit ASG name | `string` | - | yes |
| `vpc_id` | VPC ID | `string` | - | yes |
| `subnet_ids` | Subnet IDs for deployment | `list(string)` | - | yes |
| `security_group_ids` | Security group IDs | `list(string)` | - | yes |
| `eip_allocation_id` | EIP allocation ID | `string` | - | yes |
| `resource_tag_key` | Tag key for IAM conditions | `string` | `"EIPManager"` | no |
| `resource_tag_value` | Tag value for IAM conditions | `string` | - | yes |
| `standby_mode` | HA mode: `"hot"` or `"cold"` | `string` | `"cold"` | no |
| `spot_for_standby` | Use Spot for secondary (hot mode only) | `bool` | `false` | no |
| `spot_allocation_strategy` | Spot allocation strategy | `string` | `"capacity-optimized"` | no |
| `preprovisioned_standby` | Enable pre-provisioned standby (cold mode only) | `bool` | `false` | no |
| `preprovisioned_standby_state` | State: `"Stopped"` or `"Hibernated"` | `string` | `"Stopped"` | no |
| `instance_types` | Instance types for mixed policy | `list(string)` | `["t4g.nano", "t4g.micro"]` | no |
| `architecture` | CPU architecture | `string` | `"arm64"` | no |
| `ami_id` | Custom AMI ID (default: AL2023) | `string` | `null` | no |
| `user_data` | User data script | `string` | `""` | no |
| `additional_iam_policy_arns` | Additional IAM policies for EC2 | `list(string)` | `[]` | no |
| `tags` | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `asg_name` | Auto Scaling Group name |
| `asg_arn` | Auto Scaling Group ARN |
| `launch_template_id` | Launch template ID |
| `instance_profile_arn` | EC2 instance profile ARN |
| `iam_role_arn` | EC2 IAM role ARN |
| `standby_mode` | Configured standby mode |
| `preprovisioned_standby` | Whether pre-provisioned standby is enabled |
| `spot_for_standby` | Whether Spot is used for standby |
| `desired_capacity` | Desired number of running instances |

## Related Modules

- **lambda-eip-manager**: Lambda function for EIP failover (required)

## How It Works

1. **ASG Lifecycle Hooks** trigger Lambda on instance launch/terminate
2. **Lambda** associates EIP with healthy instance
3. **EventBridge** routes ASG events to Lambda
4. **IAM Conditions** restrict Lambda to tagged resources only

## Validation Rules

The module includes built-in validation:

- `preprovisioned_standby` only valid in cold mode
- `spot_for_standby` only valid in hot mode

```hcl
# ❌ Invalid: pre-provisioned standby in hot mode
standby_mode           = "hot"
preprovisioned_standby = true  # ERROR

# ❌ Invalid: spot in cold mode
standby_mode     = "cold"
spot_for_standby = true  # ERROR
```

## License

MIT
