# EC2 ASG Hot/Cold Standby with EIP Failover

Demonstrates high-availability patterns for single-instance workloads using ASG with automatic EIP failover.

## Architecture

```
                    ┌─────────────────┐
                    │   Elastic IP    │
                    │  (Static IP)    │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
     ┌────────▼────────┐          ┌─────────▼────────┐
     │  Active Instance │          │  Standby Instance │
     │   (InService)    │          │  (Warm Pool or   │
     │                  │          │   Hot Standby)   │
     └──────────────────┘          └──────────────────┘
```

Lambda function handles EIP failover via ASG lifecycle hooks.

## Standby Modes

| Mode | Running Instances | Failover Time | Cost |
|------|-------------------|---------------|------|
| **Cold (basic)** | 1 | ~60-90s | Lowest |
| **Cold (stopped)** | 1 + 1 stopped | ~30-45s | Low |
| **Cold (hibernated)** | 1 + 1 hibernated | ~40-60s | Low |
| **Hot (on-demand)** | 2 | ~10-15s | Higher |
| **Hot (spot standby)** | 1 on-demand + 1 spot | ~10-15s | Medium |

## Hot Standby

Two running instances with instant failover. Supports mixed on-demand/spot for cost optimization.

### Smart EIP Placement (prefer_on_demand)

When using spot instances for standby, the Lambda automatically keeps the EIP on the on-demand instance:

- **On failover**: Prefers on-demand instances over spot
- **On spot launch**: If on-demand exists, EIP stays on on-demand
- **On on-demand launch**: Steals EIP from spot if needed

This prevents unnecessary failovers when spot instances are interrupted.

```
┌─────────────────────────────────────────────────────────┐
│                    HOT STANDBY + SPOT                   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   ┌──────────────┐              ┌──────────────┐       │
│   │  On-Demand   │◄─── EIP ───  │    Spot      │       │
│   │  (Primary)   │   prefers    │  (Standby)   │       │
│   │              │   on-demand  │  ~70% cheaper│       │
│   └──────────────┘              └──────────────┘       │
│                                                         │
│   Spot interrupted? EIP stays on on-demand.            │
│   On-demand fails? EIP moves to spot (fallback).       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Usage

```bash
cd hot-standby
terraform init

# Both instances on-demand (highest reliability)
terraform apply -var-file=on-demand.tfvars

# Primary on-demand, standby spot (~35% cost savings)
terraform apply -var-file=spot-standby.tfvars
```

### Testing Failover

```bash
# Check current state
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=hot-standby*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,InstanceLifecycle]' \
  --output table

# Check which instance has EIP
aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=*hot-standby*" \
  --query 'Addresses[0].[PublicIp,InstanceId]' \
  --output table

# Terminate instance with EIP
ACTIVE_INSTANCE=$(aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=*hot-standby*" \
  --query 'Addresses[0].InstanceId' --output text)

aws ec2 terminate-instances --instance-ids $ACTIVE_INSTANCE

# EIP moves to other running instance within seconds
# With spot-standby: EIP prefers on-demand instance
```

## Cold Standby

Single running instance with optional pre-provisioned standby in warm pool.

### Usage

```bash
cd cold-standby
terraform init

# Basic - no pre-provisioned standby (~60-90s failover)
terraform apply -var-file=basic.tfvars

# Stopped standby - faster failover (~30-45s)
terraform apply -var-file=stopped-standby.tfvars

# Hibernated standby - preserves memory state (~40-60s)
terraform apply -var-file=hibernated-standby.tfvars
```

### Testing Failover

```bash
# Get current state
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names cold-standby-asg \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState]' \
  --output table

# Check warm pool (if using stopped/hibernated)
aws autoscaling describe-warm-pool \
  --auto-scaling-group-name cold-standby-asg \
  --query 'Instances[*].[InstanceId,LifecycleState]' \
  --output table

# Get EIP info
aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=*cold-standby*" \
  --query 'Addresses[0].[PublicIp,InstanceId]' \
  --output table

# Trigger failover by terminating active instance
ACTIVE_INSTANCE=$(aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=*cold-standby*" \
  --query 'Addresses[0].InstanceId' --output text)

aws ec2 terminate-instances --instance-ids $ACTIVE_INSTANCE

# Watch EIP move to standby
watch -n1 "aws ec2 describe-addresses \
  --filters 'Name=tag:Name,Values=*cold-standby*' \
  --query 'Addresses[0].[PublicIp,InstanceId]' --output table"
```

## Key Components

| Component | Purpose |
|-----------|---------|
| **ASG with Lifecycle Hooks** | Captures launch/terminate events before completion |
| **Lambda EIP Manager** | Associates/disassociates EIP based on lifecycle events |
| **EventBridge Rules** | Routes ASG lifecycle events to Lambda |
| **Warm Pool** | Pre-provisions stopped/hibernated instances (cold standby) |
| **prefer_on_demand** | Keeps EIP on on-demand when using spot (hot standby) |

## Lambda Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `EIP_ALLOCATION_ID` | EIP to manage | Required |
| `ASG_NAME` | ASG to monitor | Required |
| `DEPLOYMENT_MODE` | `hot-standby` or `cold-standby` | `hot-standby` |
| `PREFER_ON_DEMAND` | Keep EIP on on-demand instances | `true` |

## Requirements

- AWS CLI configured
- Terraform >= 1.0
- For hibernation: Standard AL2023 AMI (not minimal) - includes `ec2-hibinit-agent`

## Cost Comparison

| Mode | Monthly Cost (t4g.nano) | Failover Time |
|------|------------------------|---------------|
| Cold (basic) | ~$3 | ~60-90s |
| Cold (stopped) | ~$3 + EBS | ~30-45s |
| Hot (on-demand) | ~$6 | ~10-15s |
| Hot (spot standby) | ~$4 | ~10-15s |

*Costs are approximate and vary by region.*

## Cleanup

```bash
terraform destroy -var-file=<your-config>.tfvars
```
