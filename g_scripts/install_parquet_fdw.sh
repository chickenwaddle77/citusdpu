#!/bin/bash
sudo apt-get install -y postgresql-server-dev-16
if [ ! -d "/opt/parquet_fdw" ]; then
    sudo git clone https://github.com/adjust/parquet_fdw.git /opt/parquet_fdw
    cd /opt/parquet_fdw
    sudo sed -i 's/-std=c++17/-std=c++20/g' Makefile
    sudo make USE_PGXS=1 install with_llvm=no
fi
