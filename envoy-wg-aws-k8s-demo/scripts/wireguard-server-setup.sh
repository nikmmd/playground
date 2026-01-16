#!/bin/bash
set -euo pipefail

# Terminate instance on failure
trap 'echo "Setup failed, terminating instance"; shutdown -h now' ERR

# Install WireGuard
dnf install -y wireguard-tools

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

# NAT for private subnet (WireGuard server acts as NAT instance)
iptables -t nat -A POSTROUTING -s ${private_subnet_cidr} -o ens5 -j MASQUERADE
iptables -A FORWARD -s ${private_subnet_cidr} -j ACCEPT
iptables -A FORWARD -d ${private_subnet_cidr} -j ACCEPT

# Make iptables rules persistent
dnf install -y iptables-services
service iptables save

# Fetch WireGuard keys from SSM Parameter Store
SERVER_PRIVATE_KEY=$(aws ssm get-parameter \
  --name "/${project_name}/wireguard/server-private-key" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ${aws_region})

CLIENT_PUBLIC_KEY=$(aws ssm get-parameter \
  --name "/${project_name}/wireguard/client-public-key" \
  --query "Parameter.Value" \
  --output text \
  --region ${aws_region})

PRESHARED_KEY=$(aws ssm get-parameter \
  --name "/${project_name}/wireguard/preshared-key" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ${aws_region})

# Create WireGuard configuration
cat > /etc/wireguard/wg0.conf <<WGEOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = ${server_ip}/24
ListenPort = ${wireguard_port}
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = ${client_ip}/32
WGEOF

chmod 600 /etc/wireguard/wg0.conf

# Enable and start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "WireGuard server setup complete"
