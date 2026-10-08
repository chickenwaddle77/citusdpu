#!/bin/bash
set -e

echo "============================================="
echo " Starting DPU Baseline Benchmark Experiment"
echo "============================================="

# Check dependencies
echo "Checking dependencies..."
if ! command -v dstat &> /dev/null; then
    echo "dstat is not installed. Installing it now..."
    sudo apt-get update
    sudo apt-get install -y dstat
fi

if ! python3 -c "import psycopg2" &> /dev/null; then
    echo "python3-psycopg2 is not installed. Installing it now..."
    sudo apt-get update
    sudo apt-get install -y python3-psycopg2
fi
echo "Dependencies met. Proceeding..."

# Ensure directories exist
sudo mkdir -p /mnt/dataset
sudo chown -R $USER /mnt/dataset
sudo mkdir -p /opt/dpu_benchmark
sudo chown -R $USER /opt/dpu_benchmark
cp run_wiki_ingestion.py run_wiki_query.py run_parquet_query.py /opt/dpu_benchmark/

# 1. Download Datasets to Block Store
echo "[1/3] Downloading Datasets to /mnt/dataset (This may take hours)..."
wget -c https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2 -O /mnt/dataset/enwiki-latest-pages-articles.xml.bz2
# We only download the Wikipedia dump on the client node because the Python ingestion script reads it locally.
# The hits.parquet dataset is needed directly on the database server, which is handled independently.

# 2. Start Background System Monitoring
echo "[2/3] Starting CPU/Network monitoring..."
dstat -tcmnd --output /opt/dpu_benchmark/system_metrics.csv 1 > /dev/null 2>&1 &
DSTAT_PID=$!
trap 'kill $DSTAT_PID 2>/dev/null || true' EXIT
echo "  -> dstat running in background (PID: $DSTAT_PID)"

# 3. Execute Python Benchmarks
echo "[3/3] Executing Benchmarks..."
echo "--- START: WIKI INGESTION ---" >> /opt/dpu_benchmark/system_metrics.csv
python3 /opt/dpu_benchmark/run_wiki_ingestion.py
echo "--- END: WIKI INGESTION ---" >> /opt/dpu_benchmark/system_metrics.csv

echo "Sleeping for 5 seconds..."
sleep 5

echo "--- START: WIKI QUERY ---" >> /opt/dpu_benchmark/system_metrics.csv
python3 /opt/dpu_benchmark/run_wiki_query.py
echo "--- END: WIKI QUERY ---" >> /opt/dpu_benchmark/system_metrics.csv

echo "Sleeping for 5 seconds..."
sleep 5

echo "--- START: PARQUET QUERY ---" >> /opt/dpu_benchmark/system_metrics.csv
python3 /opt/dpu_benchmark/run_parquet_query.py
echo "--- END: PARQUET QUERY ---" >> /opt/dpu_benchmark/system_metrics.csv

# Cleanup is handled by the trap on EXIT
echo "  -> Benchmarks finished."

# Zip results to the dataset drive for easy extraction
tar -czvf /mnt/dataset/experiment_results.tar.gz /opt/dpu_benchmark/benchmark_results.csv /opt/dpu_benchmark/system_metrics.csv

echo "============================================="
echo " Experiment Complete!"
echo " Results archived at: /mnt/dataset/experiment_results.tar.gz"
echo "============================================="
