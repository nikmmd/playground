# Cold Standby Mode (Hibernated)
# Failover time: ~10-20 seconds
# Cost: 1x instance + hibernated instance storage
# Note: Requires EBS encryption, uses more EBS storage for RAM

name_prefix        = "cold-hib-"
standby_mode       = "cold"
cold_standby_state = "Hibernated"
