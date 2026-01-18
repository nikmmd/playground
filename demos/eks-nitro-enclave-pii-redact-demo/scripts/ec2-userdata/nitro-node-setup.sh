#!/bin/bash
set -ex

# Nitro Enclave Node Bootstrap Script
# This script is used as user-data for Karpenter-provisioned Nitro Enclave nodes.
# It runs AFTER the EKS bootstrap script.

# Install Nitro Enclaves CLI and dependencies
dnf install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel docker jq

# Configure hugepages for Nitro Enclaves
# The device plugin uses hugepages for enclave memory allocation
# Allocate 2048 x 2MB pages = 4GB for enclave workloads
echo "Configuring hugepages..."
echo 2048 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Make hugepages persistent across reboots
cat >> /etc/sysctl.d/99-hugepages.conf <<EOF
vm.nr_hugepages = 2048
EOF

# Mount hugetlbfs if not already mounted
if ! mount | grep -q hugetlbfs; then
    mkdir -p /dev/hugepages
    mount -t hugetlbfs nodev /dev/hugepages
fi

# Add hugetlbfs to fstab for persistence
if ! grep -q hugetlbfs /etc/fstab; then
    echo "nodev /dev/hugepages hugetlbfs defaults 0 0" >> /etc/fstab
fi

# Configure Nitro Enclaves allocator
# Reserve CPUs and memory for enclave workloads
cat > /etc/nitro_enclaves/allocator.yaml <<EOF
---
# Nitro Enclaves allocator configuration
# Adjust these values based on your enclave requirements
memory_mib: 3072  # 3GB reserved for enclaves
cpu_count: 2      # 2 CPUs reserved for enclaves
EOF

# Add users to 'ne' (nitro enclaves) group for enclave access
usermod -aG ne ec2-user || true
usermod -aG ne root || true

# Enable and start the Nitro Enclaves allocator service
systemctl enable --now nitro-enclaves-allocator.service

# Verify allocator is running
sleep 3
systemctl status nitro-enclaves-allocator.service || true

# Verify hugepages allocation
echo "Hugepages allocated:"
cat /proc/meminfo | grep -i huge

echo "Nitro Enclave node setup complete"
