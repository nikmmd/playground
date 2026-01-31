# Basic Cold Standby - No pre-provisioned instance
# Failover: ~60-90 seconds (launches new instance on demand)
# Cost: Lowest - only 1 running instance

preprovisioned_standby       = false
preprovisioned_standby_state = "Stopped"
instance_types               = ["t4g.nano", "t4g.micro"]
