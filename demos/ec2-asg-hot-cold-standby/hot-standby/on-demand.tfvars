# Hot Standby - Both Instances On-Demand
# Failover: ~10-15 seconds (EIP moves to already-running standby)
# Cost: Higher - 2 running on-demand instances
#
# Most reliable option - no spot interruptions to worry about.
# Use spot-standby.tfvars for ~35% cost savings with same failover time.

spot_for_standby = false
instance_types   = ["t4g.nano", "t4g.micro"]
