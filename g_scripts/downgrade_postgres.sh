#!/bin/bash
set -e

echo "Cleaning up old repositories..."
sudo rm -rf /opt/parquet_s3_fdw
sudo rm -rf /opt/parquet_fdw

echo "Purging PostgreSQL 17..."
sudo systemctl stop postgresql || true
export DEBIAN_FRONTEND=noninteractive
sudo apt-get purge -y "postgresql-17*" "postgresql-client-17"
sudo apt-get autoremove -y
sudo rm -rf /etc/postgresql/
# We leave /var/lib/postgresql/ alone, but we'll recreate the cluster.
sudo rm -rf /var/lib/postgresql/17

echo "Installing PostgreSQL 16 and Citus..."
sudo apt-get update
sudo apt-get install -y postgresql-16-citus-13.2

echo "Configuring PostgreSQL 16..."
sudo pg_conftool 16 main set shared_preload_libraries citus
sudo pg_conftool 16 main set listen_addresses '*'

echo "Configuring pg_hba.conf..."
sudo bash -c 'cat >> /etc/postgresql/16/main/pg_hba.conf <<EOF
host    all             all             10.10.1.0/24            trust
host    all             all             128.110.0.0/16          trust
EOF'

sudo sed -i 's/127.0.0.1\/32            scram-sha-256/127.0.0.1\/32            trust/' /etc/postgresql/16/main/pg_hba.conf
sudo sed -i 's/::1\/128                 scram-sha-256/::1\/128                 trust/' /etc/postgresql/16/main/pg_hba.conf

echo "Restarting PostgreSQL 16..."
sudo systemctl restart postgresql
sudo update-rc.d postgresql enable
sudo -i -u postgres psql -c "CREATE EXTENSION citus;"
echo "Downgrade on this node is complete!"
