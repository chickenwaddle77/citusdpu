#!/bin/bash
set -e

echo "============================================="
echo "1. Installing Parquet FDW from source"
echo "============================================="
sudo apt-get update
sudo apt-get install -y -V ca-certificates lsb-release wget build-essential git
if [ ! -f "apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb" ]; then
    wget https://apache.jfrog.io/artifactory/arrow/$(lsb_release --id --short | tr 'A-Z' 'a-z')/apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb
fi
sudo apt-get install -y -V ./apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb
sudo apt-get update
sudo apt-get install -y -V libarrow-dev libparquet-dev postgresql-server-dev-17 pkg-config

if [ ! -d "/opt/parquet_fdw" ]; then
    sudo git clone https://github.com/adjust/parquet_fdw.git /opt/parquet_fdw
    cd /opt/parquet_fdw
    sudo make USE_PGXS=1 install
fi

echo "============================================="
echo "2. Relocating Database to /mnt/dataset"
echo "============================================="
sudo mkdir -p /mnt/dataset
sudo systemctl stop postgresql

if [ -d "/var/lib/postgresql" ] && [ ! -L "/var/lib/postgresql" ]; then
    sudo rsync -av /var/lib/postgresql /mnt/dataset/
    sudo rm -rf /var/lib/postgresql
    sudo ln -s /mnt/dataset/postgresql /var/lib/postgresql
    sudo chown -h postgres:postgres /var/lib/postgresql
fi
sudo systemctl start postgresql

echo "============================================="
echo "3. Downloading hits.parquet for FDW"
echo "============================================="
if [ ! -f "/mnt/dataset/hits.parquet" ]; then
    sudo wget -c https://datasets.clickhouse.com/hits_compatible/hits.parquet -O /mnt/dataset/hits.parquet
fi

echo "============================================="
echo "4. Setting up Database Schema"
echo "============================================="
sudo -i -u postgres psql -d pgbench_test -c "
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

echo "Server setup complete!"

