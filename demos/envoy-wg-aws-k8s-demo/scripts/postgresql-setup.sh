#!/bin/bash
set -euo pipefail

# Terminate instance on failure
trap 'echo "Setup failed, terminating instance"; shutdown -h now' ERR

# Install PostgreSQL
dnf install -y postgresql15-server

# Initialize PostgreSQL
postgresql-setup --initdb

# Get password from SSM Parameter Store
POSTGRES_PASSWORD=$(aws ssm get-parameter \
  --name "/${project_name}/postgres/password" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region ${aws_region})

# Configure PostgreSQL to listen on all interfaces
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf

# Allow password authentication from VPC
echo "host    all             all             10.0.0.0/16             scram-sha-256" >>/var/lib/pgsql/data/pg_hba.conf
echo "host    all             all             10.8.0.0/24             scram-sha-256" >>/var/lib/pgsql/data/pg_hba.conf

# Enable and start PostgreSQL
systemctl enable postgresql
systemctl start postgresql

# Create user and database
sudo -u postgres psql <<SQLEOF
CREATE USER ${postgres_username} WITH PASSWORD '$POSTGRES_PASSWORD';
CREATE DATABASE ${postgres_db_name} OWNER ${postgres_username};
GRANT ALL PRIVILEGES ON DATABASE ${postgres_db_name} TO ${postgres_username};
SQLEOF

echo "PostgreSQL setup complete"
