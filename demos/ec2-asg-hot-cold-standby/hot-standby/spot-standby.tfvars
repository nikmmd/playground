# Hot Standby - Primary On-Demand, Standby Spot
# Failover: ~10-15 seconds (EIP moves to already-running standby)
# Cost: Medium - 1 on-demand + 1 spot (~35% savings vs all on-demand)
#
# Smart EIP Placement (prefer_on_demand=true by default):
# - EIP always stays on the on-demand instance
# - Spot interruptions don't trigger EIP failover
# - On-demand failure → EIP moves to spot (fallback)

spot_for_standby         = true
spot_allocation_strategy = "capacity-optimized"
instance_types           = ["t4g.nano", "t4g.micro"]
