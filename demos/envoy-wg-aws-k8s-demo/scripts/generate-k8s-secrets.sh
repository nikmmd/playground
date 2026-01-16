#!/bin/bash
set -euo pipefail

# This script generates Kubernetes config files from Terraform outputs
# Run this from the project root after terraform apply

cd "$(dirname "$0")/../terraform"

# Detect tofu or terraform
if command -v tofu &>/dev/null; then
  TF="tofu"
elif command -v terraform &>/dev/null; then
  TF="terraform"
else
  echo "Error: Neither tofu nor terraform found in PATH"
  exit 1
fi

echo "Using $TF to fetch outputs..."

WG_SERVER_PUBLIC_KEY=$($TF output -raw wg_server_public_key)
WG_CLIENT_PRIVATE_KEY=$($TF output -raw wg_client_private_key)
WG_PRESHARED_KEY=$($TF output -raw wg_preshared_key)
WG_SERVER_ENDPOINT=$($TF output -raw wireguard_public_ip)
POSTGRES_HOST=$($TF output -raw postgresql_private_ip)
POSTGRES_PASSWORD=$($TF output -raw postgres_password)

K8S_SECRETS="../k8s/base/secrets"
mkdir -p "$K8S_SECRETS"

# Generate WireGuard client config
cat >"$K8S_SECRETS/wg0.conf" <<EOF
[Interface]
PrivateKey = $WG_CLIENT_PRIVATE_KEY
Address = 10.8.0.2/24

[Peer]
PublicKey = $WG_SERVER_PUBLIC_KEY
PresharedKey = $WG_PRESHARED_KEY
Endpoint = $WG_SERVER_ENDPOINT:51820
AllowedIPs = 10.0.2.0/24
PersistentKeepalive = 25
EOF

# Generate PostgreSQL credentials
cat >"$K8S_SECRETS/postgres.env" <<EOF
username=demouser
password=$POSTGRES_PASSWORD
database=demodb
host=$POSTGRES_HOST
EOF

# Generate Envoy config for psql-client sidecar
cat >"$K8S_SECRETS/psql-envoy.yaml" <<'EOF'
static_resources:
  listeners:
    - name: psql_listener
      address:
        socket_address:
          address: 127.0.0.1
          port_value: 5432
      filter_chains:
        - filters:
            - name: envoy.filters.network.tcp_proxy
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy
                stat_prefix: psql_tcp
                cluster: wireguard_cluster
  clusters:
    - name: wireguard_cluster
      connect_timeout: 5s
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: wireguard_cluster
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: wireguard-client-svc
                      port_value: 15432
admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901
EOF

# Generate Envoy config for wireguard-client sidecar
# This routes to the PostgreSQL private IP through the WireGuard tunnel
cat >"$K8S_SECRETS/wg-envoy.yaml" <<EOF
static_resources:
  listeners:
    - name: wg_listener
      address:
        socket_address:
          address: 0.0.0.0
          port_value: 15432
      filter_chains:
        - filters:
            - name: envoy.filters.network.tcp_proxy
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.tcp_proxy.v3.TcpProxy
                stat_prefix: wg_tcp
                cluster: postgres_cluster
  clusters:
    - name: postgres_cluster
      connect_timeout: 5s
      type: STATIC
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: postgres_cluster
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: $POSTGRES_HOST
                      port_value: 5432
admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901
EOF

echo "Generated:"
echo "  - $K8S_SECRETS/wg0.conf"
echo "  - $K8S_SECRETS/postgres.env"
echo "  - $K8S_SECRETS/psql-envoy.yaml"
echo "  - $K8S_SECRETS/wg-envoy.yaml"
echo ""
echo "Now run: kubectl apply -k k8s/"
