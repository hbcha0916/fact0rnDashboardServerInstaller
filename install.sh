#!/bin/bash

OPT_DIR="/opt"
FACT_DASH_BOARD_DIR="/opt/Fact0rnDashboardServer3"

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi


file_exists() {
    if [ -f "$1" ]; then
        return 0  # True
    else
        return 1  # False
    fi
}

folder_exists() {
    if [ -d "$1" ]; then
        return 0  # True
    else
        return 1  # False
    fi
}

apt-get install -y python3.10-venv

if [ -x "$(command -v docker)" ]; then
    echo You already have docker installed.
else
    # Install Docker

    sudo apt-get update

    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common git

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update

    sudo apt-get install docker-ce

fi

if [ -x "$(command -v docker-compose)" ]; then
    echo You already have docker-compose installed.
else
    # Install DockerCompose

    sudo curl -L "https://github.com/docker/compose/releases/download/2.24.7/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

    sudo chmod +x /usr/local/bin/docker-compose

    sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

if [ -x "$(command -v pip3)" ]; then
    echo You already have pip3 installed.
else
    apt-get install -y python3-pip
fi

docker pull opensearchproject/opensearch:2.11.1

docker pull opensearchproject/opensearch-dashboards:2.11.1

if grep -qF "vm.max_map_count=262144" "/etc/sysctl.conf"; then
    echo "vm.max_map_count already exists in /etc/sysctl.conf"
else
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi

if grep -qF "10.5.0.1 fact0rn_net" "/etc/hosts"; then
    echo "fact0rn_net already exists in /etc/hosts"
else
    echo "10.5.0.1 fact0rn_net" >> /etc/hosts
fi

cd $OPT_DIR

if ! folder_exists "Fact0rnDashboardServer3"; then
    mkdir Fact0rnDashboardServer3
else
    systemctl stop fact-ds.service
    rm -rf Fact0rnDashboardServer3
    mkdir Fact0rnDashboardServer3
fi

cd Fact0rnDashboardServer3

git clone https://github.com/hbcha0916/fact0rnDashboardServer.git


if ! folder_exists "f0ds"; then
    python3 -m venv f0ds
else
    rm -rf f0ds
    python3 -m venv f0ds
fi

source /opt/Fact0rnDashboardServer3/f0ds/bin/activate
pip install -r ./fact0rnDashboardServer/requirements.txt
deactivate

if file_exists "/opt/Fact0rnDashboardServer3/fd.sh"; then
    rm /opt/Fact0rnDashboardServer3/fd.sh
fi

tee -a /opt/Fact0rnDashboardServer3/fd.sh > /dev/null <<EOT
#!/bin/bash
source /opt/Fact0rnDashboardServer3/f0ds/bin/activate
cd /opt/Fact0rnDashboardServer3/fact0rnDashboardServer
python3 InitServer.py
EOT

chmod +x /opt/Fact0rnDashboardServer3/fd.sh

if file_exists "/opt/Fact0rnDashboardServer3/conf.yml"; then
    rm /opt/Fact0rnDashboardServer3/conf.yml
fi

tee -a /opt/Fact0rnDashboardServer3/conf.yml > /dev/null <<EOT
LOG_level: WARN
LOG_max_byte_size: 2147483648
LOG_file_count: 3
LOG_file_dir: "./logs/"
LOG_format: "'%(asctime)s- %(filename)s - %(name)s - %(levelname)s - %(lineno)d - %(message)s'"

OS_host: "fact0rn_net"
OS_port: 9200

WebServer_host: "0.0.0.0"

APIServer_port: 2648

ViewServer_port: 2649
ViewServer_core: 4

ProxyServerPort: 8080

BackendPoolingDataTimeSec: 10
BackendPoolingLargeDataTimeSec: 30

UDP_socket_host: "0.0.0.0"
UDP_socket_port: 9092

DEV_MODE: "N"
EOT

chmod +x /opt/Fact0rnDashboardServer3/conf.yml

if file_exists "/opt/Fact0rnDashboardServer3/nginx.conf"; then
    rm /opt/Fact0rnDashboardServer3/nginx.conf
fi

tee -a /opt/Fact0rnDashboardServer3/nginx.conf > /dev/null <<EOT
user  nginx;
worker_processes  1;

error_log  /var/log/nginx/error.log warn;

pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    upstream f0ds {
      server 127.0.0.1:2649;
    }

    upstream f0ds-api {
      server 127.0.0.1:2648;
    }

    server {
      listen 8080;

      location / {
          proxy_pass http://f0ds;
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
      }

      location /api {
          proxy_pass http://f0ds-api;
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
      }
  }

    #gzip  on;
    
    include /etc/nginx/conf.d/*.conf;
}
EOT

chmod +x /opt/Fact0rnDashboardServer3/nginx.conf

if file_exists "/opt/Fact0rnDashboardServer3/docker-compose.yml"; then
    docker compose down
    rm /opt/Fact0rnDashboardServer3/docker-compose.yml
fi

tee -a /opt/Fact0rnDashboardServer3/docker-compose.yml > /dev/null <<EOT
version: '3.9'
networks:
  fact0rn_net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.0.0/16
          gateway: 10.5.0.1

services:
  nginx:
    container_name: nginx
    network_mode: "host"
    image: nginx:1.18.0
    restart: always
    volumes:
      - "./nginx.conf:/etc/nginx/nginx.conf"
    deploy: 
      resources:
        limits:
          memory: "1G"

  opensearch:
    image: opensearchproject/opensearch:2.11.1
    container_name: opensearch
    restart: always
    volumes:
      - opensearch-data:/usr/share/opensearch/data
    ports:
      - 9200:9200
      - 9300:9300
      - 9600:9600
    environment:
      - cluster.name=opensearch
      - discovery.seed_hosts=fact0rn_net
      - node.name=opensearch
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - "OPENSEARCH_JAVA_OPTS=-Xms8g -Xmx8g"
      - "DISABLE_SECURITY_PLUGIN=true"

    networks:
        fact0rn_net:
          ipv4_address: 10.5.0.5

    extra_hosts:
      - "fact0rn_net:10.5.0.1"

    deploy: 
      resources:
        limits:
          memory: "16G"

  opensearch-dashboard:
    image: opensearchproject/opensearch-dashboards:2.11.1
    depends_on:
      - opensearch
    container_name: opensearch-dashboard
    ports:
      - 5601:5601

    environment:
      - OPENSEARCH_HOSTS=http://fact0rn_net:9200
      - "DISABLE_SECURITY_DASHBOARDS_PLUGIN=true"

    networks:
      fact0rn_net:
        ipv4_address: 10.5.0.6

    extra_hosts:
      - "fact0rn_net:10.5.0.1"

    deploy: 
      resources:
        limits:
          memory: "4G"

volumes:
  opensearch-data:
EOT

chmod +x /opt/Fact0rnDashboardServer3/docker-compose.yml

docker compose up -d

echo "Please Wait..."

sleep 10


if file_exists "/opt/Fact0rnDashboardServer3/service.sh"; then
    rm /opt/Fact0rnDashboardServer3/service.sh
fi

tee -a /opt/Fact0rnDashboardServer3/service.sh > /dev/null <<'EOT'
#!/bin/bash
source /opt/Fact0rnDashboardServer3/f0ds/bin/activate
SERVER_DIR=/opt/Fact0rnDashboardServer3/fact0rnDashboardServer
cd $SERVER_DIR
counter=0
while true
do

    # Run pip install on the first iteration and every 15th iteration thereafter
    if [ $((counter % 15)) -eq 0 ]; then
        echo "Installing dependencies..."
        pip3 install -r requirements.txt
    fi
    
    # Run the hosting software
    python3 InitServer.py

    counter=$((counter + 1))
    sleep 5
done
EOT

chmod +x /opt/Fact0rnDashboardServer3/service.sh

if file_exists "/etc/systemd/system/fact-ds.service"; then
    rm /etc/systemd/system/fact-ds.service
fi
tee -a /etc/systemd/system/fact-ds.service > /dev/null <<EOT
[Unit]
Description=Fact0rnDashBoard service
[Service]
User=root
ExecStart=/opt/Fact0rnDashboardServer3/service.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOT
chmod +x /etc/systemd/system/fact-ds.service

systemctl enable fact-ds.service
systemctl enable docker.service
systemctl enable docker.socket

systemctl start fact-ds.service
systemctl start docker.service
systemctl start docker.socket