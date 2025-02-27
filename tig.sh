#!/usr/bin/env bash
#
# Simple script to deploy a TIG stack (Telegraf, InfluxDB, Grafana) 
# with SNMP trap support using Docker Compose.
#
# Usage: 
#   chmod +x setup_tig.sh
#   ./setup_tig.sh
#

set -e  # Exit on first error

# 1. Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker is not installed or not in PATH."
  echo "       Please install Docker before running this script."
  exit 1
fi

# 2. Check if Docker Compose v2 plugin is installed (or older docker-compose)
if ! docker compose version &> /dev/null; then
  if ! command -v docker-compose &> /dev/null; then
    echo "ERROR: Docker Compose is not installed."
    echo "       Please install Docker Compose (v2 or v1) before running this script."
    exit 1
  fi
fi

# 3. Create directory structure
echo "Creating directory structure..."
mkdir -p tig-stack/telegraf
mkdir -p tig-stack/influxdb-data
mkdir -p tig-stack/grafana-data

# 4. Write out docker-compose.yml
echo "Writing docker-compose.yml..."
cat << 'EOF' > tig-stack/docker-compose.yml
version: "3.9"

services:
  # -------------------------------------------------------------------
  # InfluxDB 2.x
  # -------------------------------------------------------------------
  influxdb:
    image: influxdb:2.7
    container_name: influxdb
    ports:
      - "8086:8086"
    environment:
      # Initial setup
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: admin
      DOCKER_INFLUXDB_INIT_PASSWORD: admin123
      DOCKER_INFLUXDB_INIT_ORG: MyOrg
      DOCKER_INFLUXDB_INIT_BUCKET: Telegraf
      DOCKER_INFLUXDB_INIT_ADMIN_TOKEN: MySuperSecretToken
    volumes:
      - ./influxdb-data:/var/lib/influxdb2
    restart: unless-stopped

  # -------------------------------------------------------------------
  # Telegraf
  # -------------------------------------------------------------------
  telegraf:
    image: telegraf:latest
    container_name: telegraf
    depends_on:
      - influxdb
    # Expose UDP 162 on the host to receive SNMP traps
    ports:
      - "162:162/udp"
    volumes:
      - ./telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:ro
    restart: unless-stopped

  # -------------------------------------------------------------------
  # Grafana (OSS)
  # -------------------------------------------------------------------
  grafana:
    image: grafana/grafana-oss:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: Grafana123
    volumes:
      - ./grafana-data:/var/lib/grafana
    depends_on:
      - influxdb
    restart: unless-stopped
EOF

# 5. Write out telegraf.conf for SNMP traps + InfluxDB
echo "Writing telegraf.conf..."
cat << 'EOF' > tig-stack/telegraf/telegraf.conf
# Telegraf Configuration for SNMP traps and InfluxDB output

[agent]
  omit_hostname = true
  interval = "60s"

###############################################################################
# SNMP Trap Input Plugin
###############################################################################
[[inputs.snmp_trap]]
  service_address = "udp://:162"
  # Telegraf will listen on UDP/162 (mapped in docker-compose.yml).

###############################################################################
# (Optional) SNMP Polling Input
###############################################################################
# Uncomment and configure the section below if you want to poll devices via SNMP
# [[inputs.snmp]]
#   agents = [ "udp://192.168.1.10:161", "udp://192.168.1.11:161" ]
#   version = 2
#   community = "public"
#   name = "network_device"
#   [[inputs.snmp.field]]
#     name = "sysName"
#     oid = "RFC1213-MIB::sysName.0"
#   [[inputs.snmp.field]]
#     name = "sysDescr"
#     oid = "RFC1213-MIB::sysDescr.0"

###############################################################################
# InfluxDB v2 Output Plugin
###############################################################################
[[outputs.influxdb_v2]]
  urls = ["http://influxdb:8086"]
  token = "MySuperSecretToken"
  organization = "MyOrg"
  bucket = "Telegraf"
EOF

# 6. Start the TIG stack
echo "Starting the TIG stack with Docker Compose..."
cd tig-stack

# If docker-compose v2 plugin is available, use 'docker compose', else 'docker-compose'
if docker compose version &> /dev/null; then
  docker compose up -d
else
  docker-compose up -d
fi

# 7. Print some info
echo "--------------------------------------------------------------------"
echo "TIG stack is starting up in the 'tig-stack' directory."
echo "InfluxDB:    http://localhost:8086"
echo "Grafana:     http://localhost:3000 (login: admin / Grafana123)"
echo ""
echo "InfluxDB credentials:"
echo "  Username:   admin"
echo "  Password:   admin123"
echo "  Org:        MyOrg"
echo "  Bucket:     Telegraf"
echo "  Token:      MySuperSecretToken"
echo ""
echo "Telegraf is listening for SNMP traps on UDP/162."
echo "You can edit 'telegraf/telegraf.conf' to enable SNMP polling or other input plugins."
echo ""
echo "Check logs with 'docker compose logs -f' from inside the 'tig-stack' folder."
echo "Enjoy your TIG stack!"
echo "--------------------------------------------------------------------"
