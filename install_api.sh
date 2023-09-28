#!/bin/bash

# Prompt user for port and IP address range
read -p "Enter the port you want the API to run on (default: 8000): " PORT
PORT=${PORT:-8000}

read -p "Enter the IP address range you want to allow access (default: 192.168.1.0/24): " IP_RANGE
IP_RANGE=${IP_RANGE:-192.168.1.0/24}

# Update and install necessary packages
sudo apt-get update
sudo apt-get install -y python3-pip nginx

# Install Python libraries
pip3 install Adafruit_DHT Flask gunicorn

# Add ~/.local/bin to the PATH
export PATH=$PATH:~/.local/bin

# Locate gunicorn
GUNICORN_PATH=$(which gunicorn)

# Get the Raspberry Pi's IP address
PI_IP=$(hostname -I | awk '{print $1}')

# Set up Gunicorn as a systemd service
cat <<EOL | sudo tee /etc/systemd/system/temp_humidity_api.service
[Unit]
Description=Temperature and Humidity API
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=$GUNICORN_PATH -w 4 temp_humidity_api:app -b 0.0.0.0:$PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the Gunicorn service
sudo systemctl enable temp_humidity_api.service
sudo systemctl start temp_humidity_api.service

# Set up Nginx configuration
cat <<EOL | sudo tee /etc/nginx/sites-available/temp_humidity_api
server {
    listen 80;
    server_name $PI_IP;

    location / {
        allow $IP_RANGE;
        deny all;

        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL

# Link the Nginx configuration and restart Nginx
sudo ln -s /etc/nginx/sites-available/temp_humidity_api /etc/nginx/sites-enabled
sudo nginx -t
sudo systemctl restart nginx

echo "Installation complete! The API is now running on port $PORT and accessible from the IP range $IP_RANGE."
