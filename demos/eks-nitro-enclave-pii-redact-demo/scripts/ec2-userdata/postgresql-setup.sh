#!/bin/bash
set -euo pipefail

# Terminate instance on failure
trap 'echo "Setup failed, terminating instance"; shutdown -h now' ERR

echo "Starting PostgreSQL setup..."

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

# Allow password authentication from VPC1 and VPC2
echo "host    all             all             ${vpc1_cidr}             scram-sha-256" >> /var/lib/pgsql/data/pg_hba.conf
echo "host    all             all             ${vpc2_cidr}             scram-sha-256" >> /var/lib/pgsql/data/pg_hba.conf

# Enable and start PostgreSQL
systemctl enable postgresql
systemctl start postgresql

# Create user, database, and sample data
sudo -u postgres psql <<SQLEOF
-- Create user and database
CREATE USER ${postgres_username} WITH PASSWORD '$POSTGRES_PASSWORD';
CREATE DATABASE ${postgres_db_name} OWNER ${postgres_username};
GRANT ALL PRIVILEGES ON DATABASE ${postgres_db_name} TO ${postgres_username};

-- Connect to the database
\c ${postgres_db_name}

-- Grant schema permissions
GRANT ALL ON SCHEMA public TO ${postgres_username};

-- Create user_events table
CREATE TABLE user_events (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    event_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index for common queries
CREATE INDEX idx_user_events_user_id ON user_events(user_id);
CREATE INDEX idx_user_events_event_type ON user_events(event_type);
CREATE INDEX idx_user_events_created_at ON user_events(created_at);

-- Grant table permissions
GRANT ALL PRIVILEGES ON TABLE user_events TO ${postgres_username};
GRANT USAGE, SELECT ON SEQUENCE user_events_id_seq TO ${postgres_username};

-- Create documents table for PII detection demo
-- This table will be populated via the /seed API endpoint
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Grant permissions
GRANT ALL PRIVILEGES ON TABLE documents TO ${postgres_username};
GRANT USAGE, SELECT ON SEQUENCE documents_id_seq TO ${postgres_username};

SQLEOF

# Create secure output directory for CSV files
mkdir -p /var/secure-output
chown postgres:postgres /var/secure-output
chmod 755 /var/secure-output

echo "PostgreSQL setup complete"
echo "Use POST /seed endpoint to populate sample PII documents"
