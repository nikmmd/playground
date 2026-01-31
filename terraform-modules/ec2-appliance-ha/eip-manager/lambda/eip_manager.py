"""
EIP Manager Lambda Function

Handles EIP failover for hot-standby and cold-standby deployments.
Triggered by ASG lifecycle events via EventBridge.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
autoscaling = boto3.client("autoscaling")

# Configuration from environment (read once at cold start)
EIP_ALLOCATION_ID = os.environ.get("EIP_ALLOCATION_ID")
DEPLOYMENT_MODE = os.environ.get("DEPLOYMENT_MODE", "hot-standby")
ASG_NAME = os.environ.get("ASG_NAME")
PREFER_ON_DEMAND = os.environ.get("PREFER_ON_DEMAND", "false").lower() == "true"


def get_eip_info(allocation_id: str) -> dict:
    """Get current EIP association information."""
    try:
        response = ec2.describe_addresses(AllocationIds=[allocation_id])
        if response["Addresses"]:
            return response["Addresses"][0]
    except ClientError as e:
        logger.error(f"Failed to describe EIP: {e}")
    return {}


def get_instance_lifecycle(instance_id: str) -> str:
    """Get instance lifecycle type (spot or on-demand).

    Returns 'spot', 'on-demand', or 'unknown'.
    """
    try:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        if response["Reservations"] and response["Reservations"][0]["Instances"]:
            # InstanceLifecycle is only present for spot instances
            return response["Reservations"][0]["Instances"][0].get(
                "InstanceLifecycle", "on-demand"
            )
    except ClientError as e:
        logger.error(f"Failed to describe instance {instance_id}: {e}")
    return "unknown"


def get_instance_lifecycles_batch(instance_ids: list) -> dict:
    """Get lifecycle types for multiple instances in a single API call.

    Returns dict mapping instance_id -> lifecycle ('spot' or 'on-demand').
    """
    if not instance_ids:
        return {}

    try:
        response = ec2.describe_instances(InstanceIds=instance_ids)
        result = {}
        for reservation in response["Reservations"]:
            for instance in reservation["Instances"]:
                instance_id = instance["InstanceId"]
                # InstanceLifecycle is only present for spot instances
                result[instance_id] = instance.get("InstanceLifecycle", "on-demand")
        return result
    except ClientError as e:
        logger.error(f"Failed to batch describe instances: {e}")
        return {inst_id: "unknown" for inst_id in instance_ids}


def get_healthy_instances(
    asg_name: str, exclude_instance_id: str = None, prefer_on_demand: bool = False
) -> list:
    """Get list of healthy instances in the ASG.

    If prefer_on_demand is True, on-demand instances are returned first.
    Returns list of (instance_id, lifecycle) tuples when prefer_on_demand=True,
    otherwise returns list of instance_ids for backward compatibility.
    """
    try:
        response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[asg_name]
        )
        if not response["AutoScalingGroups"]:
            return []

        instances = []
        for instance in response["AutoScalingGroups"][0]["Instances"]:
            if instance["LifecycleState"] == "InService":
                if (
                    exclude_instance_id
                    and instance["InstanceId"] == exclude_instance_id
                ):
                    continue
                instances.append(instance["InstanceId"])

        # Sort by lifecycle preference: on-demand first, then spot
        if prefer_on_demand and instances:
            # Single batch API call instead of N individual calls
            lifecycles = get_instance_lifecycles_batch(instances)

            on_demand = []
            spot = []
            for inst_id in instances:
                if lifecycles.get(inst_id) == "spot":
                    spot.append((inst_id, "spot"))
                else:
                    on_demand.append((inst_id, lifecycles.get(inst_id, "on-demand")))

            logger.info(
                f"On-demand instances: {[i[0] for i in on_demand]}, "
                f"Spot instances: {[i[0] for i in spot]}"
            )
            return on_demand + spot

        return instances
    except ClientError as e:
        logger.error(f"Failed to describe ASG: {e}")
    return []


def associate_eip(allocation_id: str, instance_id: str) -> bool:
    """Associate EIP with an instance."""
    try:
        ec2.associate_address(
            AllocationId=allocation_id,
            InstanceId=instance_id,
            AllowReassociation=True,
        )
        logger.info(f"Associated EIP {allocation_id} with instance {instance_id}")
        return True
    except ClientError as e:
        logger.error(f"Failed to associate EIP: {e}")
        return False


def disassociate_eip(association_id: str) -> bool:
    """Disassociate EIP from current instance."""
    try:
        ec2.disassociate_address(AssociationId=association_id)
        logger.info(f"Disassociated EIP association {association_id}")
        return True
    except ClientError as e:
        logger.error(f"Failed to disassociate EIP: {e}")
        return False


def complete_lifecycle_action(
    asg_name: str,
    lifecycle_hook_name: str,
    instance_id: str,
    lifecycle_action_token: str,
    result: str = "CONTINUE",
) -> None:
    """Complete the ASG lifecycle action."""
    try:
        autoscaling.complete_lifecycle_action(
            AutoScalingGroupName=asg_name,
            LifecycleHookName=lifecycle_hook_name,
            InstanceId=instance_id,
            LifecycleActionToken=lifecycle_action_token,
            LifecycleActionResult=result,
        )
        logger.info(
            f"Completed lifecycle action for {instance_id} with result {result}"
        )
    except ClientError as e:
        logger.error(f"Failed to complete lifecycle action: {e}")


def handle_instance_launching(
    event_detail: dict,
    eip_allocation_id: str,
    deployment_mode: str,
    prefer_on_demand: bool = False,
) -> dict:
    """Handle EC2 Instance-Launch Lifecycle Action."""
    instance_id = event_detail["EC2InstanceId"]
    asg_name = event_detail["AutoScalingGroupName"]
    lifecycle_hook_name = event_detail.get("LifecycleHookName")
    lifecycle_action_token = event_detail.get("LifecycleActionToken")
    destination = event_detail.get("Destination", "AutoScalingGroup")

    logger.info(
        f"Instance launching: {instance_id} in {asg_name}, destination: {destination}"
    )

    # Skip EIP association for instances going to warm pool (pre-provisioned standby)
    # These instances will be stopped/hibernated and don't need the EIP yet
    if destination == "WarmPool":
        logger.info(
            f"Instance {instance_id} is going to warm pool, skipping EIP association"
        )
        success = True
    elif deployment_mode == "cold-standby":
        # Cold standby: always associate EIP with new instance joining ASG
        eip_info = get_eip_info(eip_allocation_id)
        if eip_info.get("AssociationId"):
            disassociate_eip(eip_info["AssociationId"])
        success = associate_eip(eip_allocation_id, instance_id)
    else:
        # Hot standby: associate if no current association, or steal from spot
        eip_info = get_eip_info(eip_allocation_id)
        current_eip_instance = eip_info.get("InstanceId")

        if not current_eip_instance:
            # No current association - determine best target
            if prefer_on_demand:
                launching_lifecycle = get_instance_lifecycle(instance_id)
                if launching_lifecycle == "spot":
                    # Launching is spot - check if on-demand exists
                    # Returns list of (instance_id, lifecycle) tuples, on-demand first
                    healthy = get_healthy_instances(
                        asg_name, exclude_instance_id=None, prefer_on_demand=True
                    )
                    # Filter out launching instance, find on-demand targets
                    # Lifecycle already included in tuple - no extra API calls
                    on_demand_targets = [
                        inst_id for inst_id, lifecycle in healthy
                        if inst_id != instance_id and lifecycle != "spot"
                    ]
                    if on_demand_targets:
                        # Give EIP to on-demand instead of this spot
                        logger.info(
                            f"Launching spot {instance_id}, but on-demand {on_demand_targets[0]} exists - giving EIP to on-demand"
                        )
                        success = associate_eip(eip_allocation_id, on_demand_targets[0])
                    else:
                        # No on-demand available, give to launching spot
                        success = associate_eip(eip_allocation_id, instance_id)
                else:
                    # Launching is on-demand, give it the EIP
                    success = associate_eip(eip_allocation_id, instance_id)
            else:
                # No preference, give to launching instance
                success = associate_eip(eip_allocation_id, instance_id)
        elif prefer_on_demand:
            # Check if we should steal EIP from spot instance
            launching_lifecycle = get_instance_lifecycle(instance_id)
            current_lifecycle = get_instance_lifecycle(current_eip_instance)

            logger.info(
                f"Launching instance {instance_id} is {launching_lifecycle}, "
                f"current EIP holder {current_eip_instance} is {current_lifecycle}"
            )

            if launching_lifecycle == "on-demand" and current_lifecycle == "spot":
                # Steal EIP from spot instance to on-demand
                logger.info(
                    f"Moving EIP from spot {current_eip_instance} to on-demand {instance_id}"
                )
                if eip_info.get("AssociationId"):
                    disassociate_eip(eip_info["AssociationId"])
                success = associate_eip(eip_allocation_id, instance_id)
            else:
                logger.info(
                    f"EIP already on {current_lifecycle} instance, skipping"
                )
                success = True
        else:
            logger.info(
                f"EIP already associated with {current_eip_instance}, skipping"
            )
            success = True

    # Complete lifecycle action if this was triggered by lifecycle hook
    if lifecycle_hook_name and lifecycle_action_token:
        result = "CONTINUE" if success else "ABANDON"
        complete_lifecycle_action(
            asg_name, lifecycle_hook_name, instance_id, lifecycle_action_token, result
        )

    return {"statusCode": 200, "body": f"Instance {instance_id} launch handled"}


def handle_instance_terminating(
    event_detail: dict,
    eip_allocation_id: str,
    deployment_mode: str,
    asg_name_env: str,
    prefer_on_demand: bool = False,
) -> dict:
    """Handle EC2 Instance-Terminate Lifecycle Action."""
    instance_id = event_detail["EC2InstanceId"]
    asg_name = event_detail.get("AutoScalingGroupName", asg_name_env)
    lifecycle_hook_name = event_detail.get("LifecycleHookName")
    lifecycle_action_token = event_detail.get("LifecycleActionToken")

    logger.info(f"Instance terminating: {instance_id}")

    eip_info = get_eip_info(eip_allocation_id)

    # Check if the terminating instance has the EIP
    if eip_info.get("InstanceId") == instance_id:
        logger.info(
            f"Terminating instance {instance_id} has the EIP, initiating failover"
        )

        if deployment_mode == "hot-standby":
            # Find another healthy instance to failover to
            # prefer_on_demand ensures on-demand instances are first in the list
            healthy_instances = get_healthy_instances(
                asg_name,
                exclude_instance_id=instance_id,
                prefer_on_demand=prefer_on_demand,
            )

            if healthy_instances:
                # Disassociate from terminating instance
                if eip_info.get("AssociationId"):
                    disassociate_eip(eip_info["AssociationId"])

                # Associate with first healthy instance (on-demand first if preferred)
                # When prefer_on_demand=True, returns tuples; otherwise plain instance IDs
                if prefer_on_demand:
                    target_instance = healthy_instances[0][0]  # Extract ID from tuple
                else:
                    target_instance = healthy_instances[0]
                success = associate_eip(eip_allocation_id, target_instance)
                logger.info(f"Failed over EIP to {target_instance}: {success}")
            else:
                logger.warning("No healthy instances available for failover")
        else:
            # Cold standby: ASG will launch new instance, Lambda will handle association
            if eip_info.get("AssociationId"):
                disassociate_eip(eip_info["AssociationId"])
            logger.info("Cold standby: EIP disassociated, waiting for new instance")

    # Complete lifecycle action
    if lifecycle_hook_name and lifecycle_action_token:
        complete_lifecycle_action(
            asg_name,
            lifecycle_hook_name,
            instance_id,
            lifecycle_action_token,
            "CONTINUE",
        )

    return {"statusCode": 200, "body": f"Instance {instance_id} termination handled"}


def lambda_handler(event, context):
    """Main Lambda handler.

    Handles ASG lifecycle events only. EC2 state-change events are NOT used
    because ASG lifecycle hooks cover all termination scenarios including:
    - Manual termination (console/CLI/API)
    - Spot interruptions
    - Health check failures
    - Scale-in events
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Validate configuration (read at module level for efficiency)
    if not EIP_ALLOCATION_ID:
        logger.error("EIP_ALLOCATION_ID environment variable not set")
        return {"statusCode": 500, "body": "Configuration error"}

    if not ASG_NAME:
        logger.error("ASG_NAME environment variable not set")
        return {"statusCode": 500, "body": "Configuration error"}

    # Handle EventBridge ASG lifecycle events
    if "detail-type" not in event:
        logger.warning("Event missing detail-type, ignoring")
        return {"statusCode": 200, "body": "Event ignored"}

    detail_type = event["detail-type"]
    event_detail = event["detail"]

    # Validate ASG name matches expected (defense in depth)
    event_asg_name = event_detail.get("AutoScalingGroupName")

    # Sanity Check
    if event_asg_name != ASG_NAME:
        logger.warning(
            f"ASG name mismatch: expected '{ASG_NAME}', got '{event_asg_name}'. Ignoring event."
        )
        return {"statusCode": 200, "body": "ASG name mismatch, event ignored"}

    # https://docs.aws.amazon.com/autoscaling/ec2/userguide/lifecycle-hooks.html
    if detail_type == "EC2 Instance-launch Lifecycle Action":
        return handle_instance_launching(
            event_detail, EIP_ALLOCATION_ID, DEPLOYMENT_MODE, PREFER_ON_DEMAND
        )
    elif detail_type == "EC2 Instance-terminate Lifecycle Action":
        return handle_instance_terminating(
            event_detail,
            EIP_ALLOCATION_ID,
            DEPLOYMENT_MODE,
            ASG_NAME,
            PREFER_ON_DEMAND,
        )

    logger.warning(f"Unhandled event type: {detail_type}")
    return {"statusCode": 200, "body": "Event not handled"}
