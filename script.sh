#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Simple deploy script for NetBox + PostgreSQL + Redis
#------------------------------------------------------------------------------

# 1) Check dependencies
if ! command -v docker &> /dev/null
then
    echo "Error: Docker is not installed or not in PATH."
    exit 1
fi

if ! command -v docker-compose &> /dev/null
then
    echo "Error: docker-compose is not installed or not in PATH."
    echo "On some systems, use 'docker compose' instead. Adjust the script if needed."
    exit 1
fi

# 2) Create a folder for the NetBox setup (if not exists)
mkdir -p netbox-docker
cd netbox-docker

# 3) Create the docker-compose.yml file
cat <<EOF > docker-compose.yml
services:
  #------------------------------------------------------------------------------
  # NetBox application service
  #------------------------------------------------------------------------------
  netbox:
    image: netboxcommunity/netbox:latest
    container_name: netbox
    depends_on:
      - postgres
      - redis
    environment:
      # Basic required env vars
      ALLOWED_HOSTS: '*'
      SECRET_KEY: 'p3rVvAqx8QVAran2MqS4FJzETCXRmBIE9zSPH_3GsKGbjxhzfJ'
      DB_HOST: postgres
      DB_NAME: netbox
      DB_USER: netbox
      DB_PASS: netboxpassword
      REDIS_HOST: redis
      REDIS_PASSWORD: ''
    volumes:
      - netbox-media:/opt/netbox/netbox/media
    # Expose port 8080 internally, mapped to 8700 externally
    ports:
      - "8700:8080"
    restart: unless-stopped

  #------------------------------------------------------------------------------
  # NetBox worker (for background tasks)
  #------------------------------------------------------------------------------
  netbox-worker:
    image: netboxcommunity/netbox:latest
    container_name: netbox-worker
    depends_on:
      - netbox
    environment:
      ALLOWED_HOSTS: '*'
      SECRET_KEY: 'REPLACE_WITH_STRONG_SECRET_KEY'
      DB_HOST: postgres
      DB_NAME: netbox
      DB_USER: netbox
      DB_PASS: netboxpassword
      REDIS_HOST: redis
      REDIS_PASSWORD: ''
    command: /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py rqworker
    restart: unless-stopped

  #------------------------------------------------------------------------------
  # NetBox housekeeping (scheduled tasks)
  #------------------------------------------------------------------------------
  netbox-housekeeper:
    image: netboxcommunity/netbox:latest
    container_name: netbox-housekeeper
    depends_on:
      - netbox
    environment:
      ALLOWED_HOSTS: '*'
      SECRET_KEY: 'REPLACE_WITH_STRONG_SECRET_KEY'
      DB_HOST: postgres
      DB_NAME: netbox
      DB_USER: netbox
      DB_PASS: netboxpassword
      REDIS_HOST: redis
      REDIS_PASSWORD: ''
    command: /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py housekeeping
    restart: unless-stopped

  #------------------------------------------------------------------------------
  # PostgreSQL database
  #------------------------------------------------------------------------------
  postgres:
    image: postgres:13-alpine
    container_name: postgres
    environment:
      POSTGRES_USER: netbox
      POSTGRES_PASSWORD: netboxpassword
      POSTGRES_DB: netbox
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  #------------------------------------------------------------------------------
  # Redis caching/queue
  #------------------------------------------------------------------------------
  redis:
    image: redis:6-alpine
    container_name: redis
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  netbox-media:
EOF

# 4) Bring up the containers in detached mode
docker-compose up -d

echo "-----------------------------------------------------------------------"
echo "NetBox is now starting up. It may take a minute for initial setup."
echo "Once running, you can access NetBox at: http://<HOST_IP>:8700"
echo "-----------------------------------------------------------------------"
