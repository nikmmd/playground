# Stopped Standby - Pre-provisioned stopped instance in warm pool
# Failover: ~30-45 seconds (starts pre-existing stopped instance)
# Cost: Low - 1 running + 1 stopped (EBS storage cost only for stopped)

preprovisioned_standby       = true
preprovisioned_standby_state = "Stopped"
instance_types               = ["t4g.nano", "t4g.micro"]
