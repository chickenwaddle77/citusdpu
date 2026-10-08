import bz2
import xml.etree.ElementTree as ET
import psycopg2
import time
import csv
import os
from io import StringIO
from datetime import datetime

DB_HOST = "10.10.1.2"
DB_NAME = "pgbench_test"
DB_USER = "postgres"
FILE_PATH = '/mnt/dataset/enwiki-latest-pages-articles.xml.bz2'
CSV_FILENAME = '/opt/dpu_benchmark/benchmark_results.csv'

def run_ingestion():
    print("Starting Wikipedia Ingestion (LZ4 Compression Benchmark)...")
    start_time = time.perf_counter()
    
    conn = psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER)
    cur = conn.cursor()
    
    buffer = StringIO()
    count = 0

    try:
        with bz2.open(FILE_PATH, 'rt', encoding='utf-8') as file:
            context = ET.iterparse(file, events=('end',))
            for event, elem in context:
                if elem.tag.endswith('page'):
                    title_elem = elem.find('.//{*}title')
                    text_elem = elem.find('.//{*}text')
                    
                    if title_elem is not None and title_elem.text and text_elem is not None and text_elem.text:
                        title = title_elem.text.replace('\t', ' ').replace('\n', ' ')
                        text = text_elem.text.replace('\t', ' ').replace('\n', ' ')
                        buffer.write(f"{count}\t{title}\t{text}\n")
                        count += 1
                    
                    elem.clear()

                    if count % 10000 == 0:
                        buffer.seek(0)
                        cur.copy_from(buffer, 'wiki_articles', sep='\t')
                        conn.commit()
                        buffer = StringIO()
                        print(f"  -> Compressed and inserted {count} articles...")

        if buffer.tell() > 0:
            buffer.seek(0)
            cur.copy_from(buffer, 'wiki_articles', sep='\t')
            conn.commit()
            print(f"  -> Finished: Total {count} articles.")

    except Exception as e:
        print(f"Error during ingestion: {e}")
    finally:
        end_time = time.perf_counter()
        duration = end_time - start_time
        cur.close()
        conn.close()

    file_exists = os.path.isfile(CSV_FILENAME)
    with open(CSV_FILENAME, mode='a', newline='') as file:
        writer = csv.writer(file)
        if not file_exists:
            writer.writerow(['timestamp', 'query_name', 'hardware_state', 'iterations', 'avg_time_sec', 'min_time_sec', 'max_time_sec'])
        writer.writerow([datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "Wiki XML Ingestion (LZ4 Compression)", "Baseline (No DPU)", 1, f"{duration:.4f}", f"{duration:.4f}", f"{duration:.4f}"])
    
    print(f"Ingestion complete in {duration:.4f} seconds. Logged to CSV.")

if __name__ == "__main__":
    run_ingestion()

