"""
EIP Manager Lambda Function

Handles EIP failover for warm pool deployments (hot/cold standby).
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
ASG_NAME = os.environ.get("ASG_NAME")


def get_eip_info(allocation_id: str) -> dict:
    """Get current EIP association information."""
    try:
        response = ec2.describe_addresses(AllocationIds=[allocation_id])
        if response["Addresses"]:
            return response["Addresses"][0]
    except ClientError as e:
        logger.error(f"Failed to describe EIP: {e}")
    return {}


def get_healthy_instances(asg_name: str, exclude_instance_id: str = None) -> list:
    """Get list of healthy InService instances in the ASG."""
    try:
        response = autoscaling.describe_auto_scaling_groups(
            AutoScalingGroupNames=[asg_name]
        )
        if not response["AutoScalingGroups"]:
            return []

        instances = []
        for instance in response["AutoScalingGroups"][0]["Instances"]:
            if instance["LifecycleState"] == "InService":
                if exclude_instance_id and instance["InstanceId"] == exclude_instance_id:
                    continue
                instances.append(instance["InstanceId"])

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
        logger.info(f"Completed lifecycle action for {instance_id} with result {result}")
    except ClientError as e:
        logger.error(f"Failed to complete lifecycle action: {e}")


def handle_instance_launching(event_detail: dict) -> dict:
    """Handle EC2 Instance-Launch Lifecycle Action."""
    instance_id = event_detail["EC2InstanceId"]
    asg_name = event_detail["AutoScalingGroupName"]
    lifecycle_hook_name = event_detail.get("LifecycleHookName")
    lifecycle_action_token = event_detail.get("LifecycleActionToken")
    destination = event_detail.get("Destination", "AutoScalingGroup")

    logger.info(f"Instance launching: {instance_id} in {asg_name}, destination: {destination}")

    # Skip EIP association for instances going to warm pool
    # They will get EIP when promoted to InService
    if destination == "WarmPool":
        logger.info(f"Instance {instance_id} going to warm pool, skipping EIP association")
        success = True
    else:
        # Instance joining ASG (either new or from warm pool)
        eip_info = get_eip_info(EIP_ALLOCATION_ID)
        current_holder = eip_info.get("InstanceId")

        if not current_holder:
            # No instance has EIP - associate with this one
            success = associate_eip(EIP_ALLOCATION_ID, instance_id)
        else:
            # EIP already on another instance (rolling update scenario)
            # Don't steal EIP - let termination hook handle transfer
            # This ensures EIP stays on healthy instance until new one is confirmed healthy
            logger.info(f"EIP already on {current_holder}, skipping (termination hook will transfer)")
            success = True

    # Complete lifecycle action
    if lifecycle_hook_name and lifecycle_action_token:
        result = "CONTINUE" if success else "ABANDON"
        complete_lifecycle_action(
            asg_name, lifecycle_hook_name, instance_id, lifecycle_action_token, result
        )

    return {"statusCode": 200, "body": f"Instance {instance_id} launch handled"}


def handle_instance_terminating(event_detail: dict) -> dict:
    """Handle EC2 Instance-Terminate Lifecycle Action."""
    instance_id = event_detail["EC2InstanceId"]
    asg_name = event_detail.get("AutoScalingGroupName", ASG_NAME)
    lifecycle_hook_name = event_detail.get("LifecycleHookName")
    lifecycle_action_token = event_detail.get("LifecycleActionToken")

    logger.info(f"Instance terminating: {instance_id}")

    eip_info = get_eip_info(EIP_ALLOCATION_ID)

    # Check if the terminating instance has the EIP
    if eip_info.get("InstanceId") == instance_id:
        logger.info(f"Terminating instance {instance_id} has EIP, initiating failover")

        # Disassociate from terminating instance
        if eip_info.get("AssociationId"):
            disassociate_eip(eip_info["AssociationId"])

        # Find another healthy instance to failover to
        healthy_instances = get_healthy_instances(asg_name, exclude_instance_id=instance_id)

        if healthy_instances:
            target_instance = healthy_instances[0]
            success = associate_eip(EIP_ALLOCATION_ID, target_instance)
            logger.info(f"Failed over EIP to {target_instance}: {success}")
        else:
            logger.warning("No healthy instances for failover, waiting for new instance")

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

    Handles ASG lifecycle events for EIP failover.
    """
    logger.info(f"Received event: {json.dumps(event)}")

    # Validate configuration
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

    # Validate ASG name matches expected
    event_asg_name = event_detail.get("AutoScalingGroupName")
    if event_asg_name != ASG_NAME:
        logger.warning(f"ASG mismatch: expected '{ASG_NAME}', got '{event_asg_name}'")
        return {"statusCode": 200, "body": "ASG mismatch, event ignored"}

    if detail_type == "EC2 Instance-launch Lifecycle Action":
        return handle_instance_launching(event_detail)
    elif detail_type == "EC2 Instance-terminate Lifecycle Action":
        return handle_instance_terminating(event_detail)

    logger.warning(f"Unhandled event type: {detail_type}")
    return {"statusCode": 200, "body": "Event not handled"}
