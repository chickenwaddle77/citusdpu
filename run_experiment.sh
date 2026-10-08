#!/bin/bash
set -e

echo "============================================="
echo " Starting DPU Baseline Benchmark Experiment"
echo "============================================="

# Ensure directories exist
sudo mkdir -p /mnt/dataset
sudo chown -R $USER:$(id -gn $USER) /mnt/dataset
sudo mkdir -p /opt/dpu_benchmark
sudo chown -R $USER:$(id -gn $USER) /opt/dpu_benchmark
cp run_wiki_ingestion.py run_wiki_query.py run_parquet_query.py /opt/dpu_benchmark/

# 1. Download Datasets to Block Store
echo "[1/5] Downloading Datasets to /mnt/dataset (This may take hours)..."
wget -c https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2 -O /mnt/dataset/enwiki-latest-pages-articles.xml.bz2
wget -c https://datasets.clickhouse.com/hits_compatible/hits.parquet -O /mnt/dataset/hits.parquet

# 2. Setup Database Storage Relocation
echo "[2/5] Relocating Database to Block Store to prevent root disk crash..."
sudo systemctl stop postgresql
sudo rsync -av /var/lib/postgresql /mnt/dataset/
sudo rm -rf /var/lib/postgresql
sudo ln -s /mnt/dataset/postgresql /var/lib/postgresql
sudo chown -h postgres:postgres /var/lib/postgresql
sudo systemctl start postgresql

# 3. Setup Database Schema
echo "[3/5] Configuring Database Tables..."
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

# 4. Start Background System Monitoring
echo "[4/5] Starting CPU/Network monitoring..."
dstat -tcmnd --output /opt/dpu_benchmark/system_metrics.csv 1 > /dev/null 2>&1 &
DSTAT_PID=$!
trap 'kill $DSTAT_PID 2>/dev/null || true' EXIT
echo "  -> dstat running in background (PID: $DSTAT_PID)"

# 5. Execute Python Benchmarks
echo "[5/5] Executing Benchmarks..."
python3 /opt/dpu_benchmark/run_wiki_ingestion.py
python3 /opt/dpu_benchmark/run_wiki_query.py
python3 /opt/dpu_benchmark/run_parquet_query.py

# Cleanup is handled by the trap on EXIT
echo "  -> Benchmarks finished."

# Zip results to the dataset drive for easy extraction
tar -czvf /mnt/dataset/experiment_results.tar.gz /opt/dpu_benchmark/benchmark_results.csv /opt/dpu_benchmark/system_metrics.csv

echo "============================================="
echo " Experiment Complete!"
echo " Results archived at: /mnt/dataset/experiment_results.tar.gz"
echo "============================================="

