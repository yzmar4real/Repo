#!/bin/bash
set -e

# --- CONFIGURATION VARIABLES ---
MYSQL_ROOT_PASSWORD="Abcd1234$"
MYSQL_DB_PASSWORD="Abcd1234$"
TUNNEL_TOKEN="eyJhIjoiYWYwYTY3MzEwNDYxYjZiODlmNmQzNjg2NjQ1NDg5ODQiLCJ0IjoiNGY2YzJhZjktNWY1OS00ZWQwLTk3MDMtZjQ3MTNjMzE1NDA4IiwicyI6IlpUa3lZbVV4TVRBdFlqTmhZaTAwTnpKaUxXRXhOMll0WWpVd01qaG1NbUUyTjJGayJ9"

# Function to check if the last command executed successfully
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: Previous command failed to execute successfully."
        exit 1
    fi
}

# --- INSTALL DOCKER & DOCKER COMPOSE ---
echo "Installing Docker and Docker Compose..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
check_status
sudo apt-get -o Dpkg::Options::="--force-confnew" --force-yes -fuy dist-upgrade
check_status
sudo apt-get install apt-transport-https ca-certificates curl software-properties-common -y
check_status
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
check_status
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
check_status
sudo apt-get update
check_status
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
check_status
sudo systemctl enable docker
check_status
sudo systemctl start docker
check_status

# Install Docker Compose
echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
check_status

# --- ADD USER TO DOCKER GROUP ---
echo "Adding user to Docker group..."
sudo usermod -aG docker $USER
check_status
echo "You need to log out and log back in for changes to take effect."
echo "Proceeding with script execution..."

# --- CREATE MANAGEMENT FOLDERS ---
echo "Creating management folder structure..."
mkdir -p ~/Mgt/Portainer/data
mkdir -p ~/Mgt/GuacMgt/mysql-init ~/Mgt/GuacMgt/db_data ~/Mgt/GuacMgt/Guacamole/extensions
mkdir -p ~/Mgt/Cloudflare
check_status

# --- CREATE PORTAINER DOCKER COMPOSE ---
echo "Creating Portainer docker-compose.yml..."
cat <<EOF > ~/Mgt/Portainer/docker-compose.yml
version: "3"
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - "9000:9000"
    volumes:
      - ./data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
EOF


# --- CREATE GUACAMOLE DOCKER COMPOSE ---
echo "Creating Guacamole docker-compose.yml..."
cat > ~/Mgt/GuacMgt/docker-compose.yml <<EOF
version: "3"
services:
  mysql:
    image: mysql:5.7
    container_name: guac-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "$MYSQL_ROOT_PASSWORD"
      MYSQL_DATABASE: "guacamole_db"
      MYSQL_USER: "guacamole_user"
      MYSQL_PASSWORD: "$MYSQL_DB_PASSWORD"
    volumes:
      - ./db_data:/var/lib/mysql
      - ./mysql-init:/docker-entrypoint-initdb.d
    networks:
      - guac-network

  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: unless-stopped
    ports:
      - "4822:4822"
    networks:
      - guac-network

  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    restart: unless-stopped
    depends_on:
      - mysql
      - guacd
    environment:
      MYSQL_HOSTNAME: mysql
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacamole_user
      MYSQL_PASSWORD: "$MYSQL_DB_PASSWORD"
      GUACD_HOSTNAME: guacd
    volumes:
      - ./Guacamole:/etc/guacamole
    ports:
      - "8080:8080"
    networks:
      - guac-network

networks:
  guac-network:
EOF

# Generate the Guacamole MySQL initialization SQL script if it doesn't exist
INIT_SQL_FILE="$HOME/Mgt/GuacMgt/mysql-init/guacamole-init.sql"
if [ ! -f "$INIT_SQL_FILE" ]; then
    echo "Generating Guacamole MySQL initialization script..."
    sudo docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql > "$INIT_SQL_FILE"
else
    echo "Initialization SQL script already exists. Skipping generation."
fi

# --- CREATE CLOUDFLARE DOCKER COMPOSE ---
echo "Creating Cloudflare docker-compose.yml..."
cat <<EOF > ~/Mgt/Cloudflare/docker-compose.yml
version: "3"
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=$TUNNEL_TOKEN
EOF

# --- DEPLOY ALL SERVICES ---
echo "Deploying Portainer..."
sudo docker-compose -f ~/Mgt/Portainer/docker-compose.yml up -d
check_status

echo "Deploying Guacamole..."
cd ~/Mgt/GuacMgt
sudo docker-compose up -d
check_status

echo "Deploying Cloudflare Tunnel..."
cd ~/Mgt/Cloudflare
sudo docker-compose up -d
check_status

echo "Setup completed successfully!"
echo "Portainer: http://<server-ip>:9000"
echo "Guacamole: http://<server-ip>:8080/guacamole"
echo "Cloudflare Tunnel is running. Check logs with: docker logs cloudflared"
