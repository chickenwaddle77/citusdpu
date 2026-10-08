#!/bin/bash
set -e
sudo apt-get update
sudo apt-get install -y -V ca-certificates lsb-release wget build-essential git postgresql-server-dev-16 pkg-config
if [ ! -f "apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb" ]; then
    wget https://apache.jfrog.io/artifactory/arrow/$(lsb_release --id --short | tr 'A-Z' 'a-z')/apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb
fi
sudo apt-get install -y -V ./apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb
sudo apt-get update
sudo apt-get install -y -V libarrow-dev libparquet-dev

if [ -d "/opt/parquet_fdw" ]; then
    sudo rm -rf /opt/parquet_fdw
fi

sudo git clone https://github.com/adjust/parquet_fdw.git /opt/parquet_fdw
cd /opt/parquet_fdw
sudo sed -i 's/-std=c++17/-std=c++20/g' Makefile
sudo make USE_PGXS=1 install with_llvm=no

echo "Done installing parquet_fdw on worker!"
