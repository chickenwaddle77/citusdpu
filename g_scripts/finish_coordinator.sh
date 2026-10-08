#!/bin/bash
set -e

echo "Relocating Database to Block Store..."
sudo systemctl stop postgresql
sudo mkdir -p /mnt/dataset
sudo chown -R $USER:$(id -gn $USER) /mnt/dataset

if [ -d "/var/lib/postgresql" ] && [ ! -L "/var/lib/postgresql" ]; then
    sudo rsync -av /var/lib/postgresql /mnt/dataset/
    sudo rm -rf /var/lib/postgresql
    sudo ln -s /mnt/dataset/postgresql /var/lib/postgresql
    sudo chown -h postgres:postgres /var/lib/postgresql
fi
sudo systemctl start postgresql

echo "Setting up Cluster..."
sudo -i -u postgres psql -c "SELECT citus_set_coordinator_host('10.10.1.2', 5432);"
sudo -i -u postgres psql -c "SELECT * from citus_add_node('10.10.1.1', 5432);"
sudo -i -u postgres psql -c "SELECT * from citus_add_node('10.10.1.3', 5432);"

echo "Downloading hits.parquet (if not exists)..."
if [ ! -f "/mnt/dataset/hits.parquet" ]; then
    sudo wget -c https://datasets.clickhouse.com/hits_compatible/hits.parquet -O /mnt/dataset/hits.parquet
fi

echo "Setting up Database Schema..."
sudo -i -u postgres psql -c "CREATE DATABASE pgbench_test;" || true
sudo -i -u postgres psql -d pgbench_test -c "
CREATE EXTENSION IF NOT EXISTS citus;

DROP TABLE IF EXISTS wiki_articles CASCADE;
CREATE TABLE wiki_articles (id bigint, title text, full_text text) USING columnar;
ALTER TABLE wiki_articles SET (columnar.compression = 'lz4');
SELECT create_distributed_table('wiki_articles', 'id');

CREATE EXTENSION IF NOT EXISTS parquet_fdw;
CREATE SERVER IF NOT EXISTS parquet_server FOREIGN DATA WRAPPER parquet_fdw;

DROP FOREIGN TABLE IF EXISTS web_hits_parquet CASCADE;
CREATE FOREIGN TABLE web_hits_parquet (
    \"WatchID\" bigint, \"ClientIP\" bigint, \"RequestURL\" text,
    \"UserAgent\" text, \"EventTime\" timestamp, \"Title\" text
) SERVER parquet_server OPTIONS (filename '/mnt/dataset/hits.parquet');
"

