#!/bin/bash
set -euo pipefail

# Prompt user for port and IP address range
read -p "Enter the port you want the API to run on (default: 8000): " PORT
PORT=${PORT:-8000}

read -p "Enter the IP address range you want to allow access (default: 192.168.1.0/24): " IP_RANGE
IP_RANGE=${IP_RANGE:-192.168.1.0/24}

# Prompt for SSL configuration
read -p "Do you want to enable HTTPS? (y/n, default: y): " ENABLE_HTTPS
ENABLE_HTTPS=${ENABLE_HTTPS:-y}

# If HTTPS is enabled, prompt for HTTPS port
if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  read -p "Enter the port you want to use for HTTPS (default: 8443): " HTTPS_PORT
  HTTPS_PORT=${HTTPS_PORT:-8443}
fi

# If HTTPS is enabled, prompt for certificate paths
if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  read -p "Enter the path to your Let's Encrypt certificate (default: /etc/letsencrypt/live/$(hostname)/fullchain.pem): " LE_CERT_PATH
  LE_CERT_PATH=${LE_CERT_PATH:-/etc/letsencrypt/live/$(hostname)/fullchain.pem}
  
  read -p "Enter the path to your Let's Encrypt private key (default: /etc/letsencrypt/live/$(hostname)/privkey.pem): " LE_KEY_PATH
  LE_KEY_PATH=${LE_KEY_PATH:-/etc/letsencrypt/live/$(hostname)/privkey.pem}

  read -p "Do you want to use Tailscale certificates? (y/n, default: n): " USE_TAILSCALE
  USE_TAILSCALE=${USE_TAILSCALE:-n}
  
  if [[ "${USE_TAILSCALE,,}" == "y" ]]; then
    read -p "Enter the path to your Tailscale certificate (default: /var/lib/tailscale/certs/$(hostname)/cert.pem): " TS_CERT_PATH
    TS_CERT_PATH=${TS_CERT_PATH:-/var/lib/tailscale/certs/$(hostname)/cert.pem}
    
    read -p "Enter the path to your Tailscale private key (default: /var/lib/tailscale/certs/$(hostname)/key.pem): " TS_KEY_PATH
    TS_KEY_PATH=${TS_KEY_PATH:-/var/lib/tailscale/certs/$(hostname)/key.pem}
  fi
fi

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

# Create Nginx configuration
if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  # HTTPS configuration
  echo "📋 Setting up Nginx with HTTPS support..."
  
  # Check if the Let's Encrypt certificates exist
  if [[ ! -f "$LE_CERT_PATH" || ! -f "$LE_KEY_PATH" ]]; then
    echo "❌ Let's Encrypt certificates not found at specified paths. Please ensure they exist before continuing."
    echo "Specified paths:"
    echo "Certificate: $LE_CERT_PATH"
    echo "Key: $LE_KEY_PATH"
    exit 1
  fi

  # Set up Nginx with HTTPS configuration
  if [[ "${USE_TAILSCALE,,}" == "y" ]]; then
    # Check if the Tailscale certificates exist
    if [[ ! -f "$TS_CERT_PATH" || ! -f "$TS_KEY_PATH" ]]; then
      echo "❌ Tailscale certificates not found at specified paths. Please ensure they exist before continuing."
      echo "Specified paths:"
      echo "Certificate: $TS_CERT_PATH"
      echo "Key: $TS_KEY_PATH"
      exit 1
    fi
    
    echo "🔄 Configuring Nginx with both Let's Encrypt and Tailscale certificates..."
    
    cat <<EOL | sudo tee /etc/nginx/sites-available/temp_humidity_api
server {
    listen 80;
    server_name $PI_IP;
    
    # Redirect all HTTP traffic to HTTPS
    location / {
        return 301 https://\$host:$HTTPS_PORT\$request_uri;
    }
}

# Let's Encrypt HTTPS server
server {
    listen $HTTPS_PORT ssl;
    server_name $PI_IP;
    
    ssl_certificate $LE_CERT_PATH;
    ssl_certificate_key $LE_KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    location / {
        allow $IP_RANGE;
        deny all;
        
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Tailscale HTTPS server
server {
    listen $HTTPS_PORT ssl;
    server_name $PI_IP.tailnet-name.ts.net;
    
    ssl_certificate $TS_CERT_PATH;
    ssl_certificate_key $TS_KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    
    location / {
        allow $IP_RANGE;
        deny all;
        
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
  else
    # Only Let's Encrypt configuration
    echo "🔄 Configuring Nginx with Let's Encrypt certificates..."
    
    cat <<EOL | sudo tee /etc/nginx/sites-available/temp_humidity_api
server {
    listen 80;
    server_name $PI_IP;
    
    # Redirect all HTTP traffic to HTTPS
    location / {
        return 301 https://\$host:$HTTPS_PORT\$request_uri;
    }
}

server {
    listen $HTTPS_PORT ssl;
    server_name $PI_IP;
    
    ssl_certificate $LE_CERT_PATH;
    ssl_certificate_key $LE_KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    location / {
        allow $IP_RANGE;
        deny all;
        
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
  fi
else
  # HTTP-only configuration (original)
  echo "📋 Setting up Nginx with HTTP only (no HTTPS)..."
  
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
fi

# Remove any existing symlink before creating a new one
sudo rm -f /etc/nginx/sites-enabled/temp_humidity_api

# Link the Nginx configuration and restart Nginx
sudo ln -s /etc/nginx/sites-available/temp_humidity_api /etc/nginx/sites-enabled
sudo nginx -t
if [ $? -ne 0 ]; then
  echo "❌ Nginx configuration test failed. Please check the configuration and try again."
  exit 1
fi
sudo systemctl restart nginx

echo "✅ Installation complete!"
if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  echo "🔒 The API is now running with HTTPS enabled on port $HTTPS_PORT."
  echo "🌐 Access URLs:"
  echo "  - HTTPS: https://$PI_IP:$HTTPS_PORT/metrics"
  if [[ "${USE_TAILSCALE,,}" == "y" ]]; then
    echo "  - Tailscale HTTPS: https://$PI_IP.tailnet-name.ts.net:$HTTPS_PORT/metrics"
  fi
else
  echo "🌐 The API is now running on HTTP: http://$PI_IP/metrics"
fi
echo "🔐 Access is restricted to IP range: $IP_RANGE"
echo "🔧 Local port: $PORT"
