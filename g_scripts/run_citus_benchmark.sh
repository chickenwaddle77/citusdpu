#!/bin/bash
set -e

echo "=========================================="
echo "3. CLUSTER FORMATION (Coordinator node only)"
echo "=========================================="
sudo -i -u postgres psql -c "SELECT citus_set_coordinator_host('10.10.1.2', 5432);"
sudo -i -u postgres psql -c "SELECT * from citus_add_node('10.10.1.1', 5432);"
sudo -i -u postgres psql -c "SELECT * from citus_add_node('10.10.1.3', 5432);"
sudo -i -u postgres psql -c "SELECT * FROM master_get_active_worker_nodes();"

echo "=========================================="
echo "4. DATABASE SETUP (Coordinator node only)"
echo "=========================================="
sudo -i -u postgres psql -c "CREATE DATABASE pgbench_test;" || true
sudo -i -u postgres psql -d pgbench_test -c "CREATE EXTENSION IF NOT EXISTS citus;"
sudo -i -u postgres pgbench -i -I dtg pgbench_test
sudo -i -u postgres psql -d pgbench_test -c "SELECT create_distributed_table('pgbench_accounts', 'aid');"

echo "=========================================="
echo "5. DATA GENERATION (Coordinator node only)"
echo "=========================================="
sudo -i -u postgres pgbench -i -I g -s 1000 pgbench_test

echo "=========================================="
echo "6. BENCHMARK EXECUTION (Coordinator node only)"
echo "=========================================="
sudo -i -u postgres pgbench -c 16 -j 4 -T 60 pgbench_test

