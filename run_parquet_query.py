import psycopg2
import time
import statistics
import csv
import os
from datetime import datetime

DB_HOST = "10.10.1.2"
DB_NAME = "pgbench_test"
DB_USER = "postgres"
CSV_FILENAME = '/opt/dpu_benchmark/benchmark_results.csv'

QUERY_NAME = "ClickBench String Scan (Parquet FDW Decompression)"
QUERY = """SELECT count(*) FROM web_hits_parquet WHERE "RequestURL" ILIKE '%checkout%' OR "Title" ILIKE '%Cart%';"""
ITERATIONS = 5

def run_benchmark():
    print(f"\nStarting {QUERY_NAME}...")
    conn = psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER)
    conn.autocommit = True
    cur = conn.cursor()

    try:
        print("  -> Running warm-up query...")
        cur.execute(QUERY)
        cur.fetchone()
        
        execution_times = []
        for i in range(ITERATIONS):
            start_time = time.perf_counter()
            cur.execute(QUERY)
            cur.fetchone()
            duration = time.perf_counter() - start_time
            execution_times.append(duration)
            print(f"  -> Iteration {i+1} completed in {duration:.4f} seconds.")

        avg_time = statistics.mean(execution_times)
        min_time = min(execution_times)
        max_time = max(execution_times)

        file_exists = os.path.isfile(CSV_FILENAME)
        with open(CSV_FILENAME, mode='a', newline='') as file:
            writer = csv.writer(file)
            if not file_exists:
                writer.writerow(['timestamp', 'query_name', 'hardware_state', 'iterations', 'avg_time_sec', 'min_time_sec', 'max_time_sec'])
            writer.writerow([datetime.now().strftime("%Y-%m-%d %H:%M:%S"), QUERY_NAME, "Baseline (No DPU)", ITERATIONS, f"{avg_time:.4f}", f"{min_time:.4f}", f"{max_time:.4f}"])
        print(f"Benchmark complete. Avg: {avg_time:.4f} sec. Logged to CSV.")

    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    run_benchmark()

