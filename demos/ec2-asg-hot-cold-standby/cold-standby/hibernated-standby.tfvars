# Hibernated Standby - Pre-provisioned hibernated instance in warm pool
# Failover: ~40-60 seconds (resumes hibernated instance with preserved memory)
# Cost: Low - 1 running + 1 hibernated (EBS storage cost for stopped + hibernation data)
# Note: Requires standard AL2023 AMI (not minimal) for ec2-hibinit-agent

preprovisioned_standby       = true
preprovisioned_standby_state = "Hibernated"
instance_types               = ["t4g.nano", "t4g.micro"]
