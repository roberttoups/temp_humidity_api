#!/bin/bash
# filepath: /Users/toups/Dropbox/git/temp_humidity_api/install_enhanced_api.sh
set -euo pipefail

# Function for displaying messages with emojis
function log_message() {
  local message="$1"
  local emoji="$2"
  echo "${emoji} ${message}"
}

log_message "Starting Temperature and Humidity API installation" "🚀"

# ========================
# Configuration parameters
# ========================

# Prompt for API configuration
log_message "Configuring API settings..." "⚙️"

read -p "Enter the HTTP port for the API (default: 5000): " HTTP_PORT
HTTP_PORT=${HTTP_PORT:-5000}

log_message "Configuring HTTPS settings..." "🔒"
read -p "Do you want to enable HTTPS? (y/n, default: y): " ENABLE_HTTPS
ENABLE_HTTPS=${ENABLE_HTTPS:-y}

# Default API key (generate a random one if not provided)
DEFAULT_API_KEY=$(openssl rand -hex 16)

if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  read -p "Enter the HTTPS port for the API (default: 8443): " HTTPS_PORT
  HTTPS_PORT=${HTTPS_PORT:-8443}
  
  read -p "Do you want to configure multiple domains with different certificates? (y/n, default: n): " MULTI_DOMAIN
  MULTI_DOMAIN=${MULTI_DOMAIN:-n}
  
  if [[ "${MULTI_DOMAIN,,}" == "y" ]]; then
    log_message "Setting up multi-domain certificate configuration" "🔄"
    
    # Create a temp file to store certificate configurations
    CERT_CONFIG_FILE="/tmp/cert_config.json"
    echo "{" > "$CERT_CONFIG_FILE"
    
    # Add default certificate
    read -p "Enter the path to your default SSL certificate (default: /etc/letsencrypt/live/$(hostname)/fullchain.pem): " CERT_PATH
    CERT_PATH=${CERT_PATH:-/etc/letsencrypt/live/$(hostname)/fullchain.pem}
    
    read -p "Enter the path to your default SSL private key (default: /etc/letsencrypt/live/$(hostname)/privkey.pem): " KEY_PATH
    KEY_PATH=${KEY_PATH:-/etc/letsencrypt/live/$(hostname)/privkey.pem}
    
    # Ask for additional domains and certificates
    log_message "Now let's configure additional domain certificates" "🔧"
    log_message "You'll be asked to enter domain names and their certificate paths" "📋"
    log_message "Press Enter without typing a domain name when you're done" "✅"
    
    FIRST_DOMAIN=true
    DOMAIN_COUNT=0
    
    while true; do
      read -p "Enter a domain name (or press Enter to finish): " DOMAIN_NAME
      if [[ -z "$DOMAIN_NAME" ]]; then
        break
      fi
      
      read -p "Enter the path to the SSL certificate for $DOMAIN_NAME: " DOMAIN_CERT
      read -p "Enter the path to the SSL key for $DOMAIN_NAME: " DOMAIN_KEY
      
      # Check if files exist
      if [[ ! -f "$DOMAIN_CERT" || ! -f "$DOMAIN_KEY" ]]; then
        log_message "Warning: Certificate or key not found for $DOMAIN_NAME" "⚠️"
        read -p "Do you want to continue anyway? (y/n, default: n): " CONTINUE_DOMAIN
        CONTINUE_DOMAIN=${CONTINUE_DOMAIN:-n}
        if [[ "${CONTINUE_DOMAIN,,}" != "y" ]]; then
          continue
        fi
      fi
      
      # Add to the config file
      if [[ "$FIRST_DOMAIN" == "true" ]]; then
        FIRST_DOMAIN=false
      else
        echo "," >> "$CERT_CONFIG_FILE"
      fi
      
      # Escape quotes in paths
      DOMAIN_CERT="${DOMAIN_CERT//\"/\\\"}"
      DOMAIN_KEY="${DOMAIN_KEY//\"/\\\"}"
      
      echo "  \"$DOMAIN_NAME\": {" >> "$CERT_CONFIG_FILE"
      echo "    \"cert_path\": \"$DOMAIN_CERT\"," >> "$CERT_CONFIG_FILE"
      echo "    \"key_path\": \"$DOMAIN_KEY\"" >> "$CERT_CONFIG_FILE"
      echo "  }" >> "$CERT_CONFIG_FILE"
      
      DOMAIN_COUNT=$((DOMAIN_COUNT + 1))
      log_message "Added configuration for $DOMAIN_NAME" "✅"
    done
    
    echo "}" >> "$CERT_CONFIG_FILE"
    
    if [[ $DOMAIN_COUNT -eq 0 ]]; then
      log_message "No additional domains configured" "ℹ️"
      MULTI_DOMAIN="n"
    else
      log_message "Configured $DOMAIN_COUNT additional domains" "✅"
      
      # Copy the config file to a permanent location
      API_DIR="/home/$(whoami)/temp_humidity_api"
      mkdir -p "$API_DIR"
      CERT_CONFIG_DEST="$API_DIR/certificates.json"
      cp "$CERT_CONFIG_FILE" "$CERT_CONFIG_DEST"
      log_message "Certificate configuration saved to $CERT_CONFIG_DEST" "📄"
    fi
  else
    # Single domain certificate configuration
    read -p "Enter the path to your SSL certificate (default: /etc/letsencrypt/live/$(hostname)/fullchain.pem): " CERT_PATH
    CERT_PATH=${CERT_PATH:-/etc/letsencrypt/live/$(hostname)/fullchain.pem}
    
    read -p "Enter the path to your SSL private key (default: /etc/letsencrypt/live/$(hostname)/privkey.pem): " KEY_PATH
    KEY_PATH=${KEY_PATH:-/etc/letsencrypt/live/$(hostname)/privkey.pem}
  fi
  
  # Check if the default certificate files exist
  if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
    log_message "Warning: Certificate or key not found at specified path." "⚠️"
    log_message "Certificate: $CERT_PATH" "📄"
    log_message "Key: $KEY_PATH" "🔑"
    log_message "You may need to install them manually." "ℹ️"
    
    read -p "Do you want to continue anyway? (y/n, default: n): " CONTINUE_WITHOUT_CERT
    CONTINUE_WITHOUT_CERT=${CONTINUE_WITHOUT_CERT:-n}
    if [[ "${CONTINUE_WITHOUT_CERT,,}" != "y" ]]; then
      log_message "Installation aborted." "❌"
      exit 1
    fi
    log_message "Continuing without certificate validation..." "⚠️"
  else
    log_message "Default certificate files found." "✅"
  fi
fi

# Security configuration
log_message "Configuring security settings..." "🔐"

read -p "Do you want to enable API key authentication? (y/n, default: y): " ENABLE_AUTH
ENABLE_AUTH=${ENABLE_AUTH:-y}

if [[ "${ENABLE_AUTH,,}" == "y" ]]; then
  read -p "Enter an API key (leave blank to generate one): " API_KEY
  API_KEY=${API_KEY:-$DEFAULT_API_KEY}
  log_message "API key set. Make sure to keep this key secure." "🔑"
  if [[ "$API_KEY" == "$DEFAULT_API_KEY" ]]; then
    log_message "Generated API key: $API_KEY" "🔑"
  fi
fi

read -p "Enter allowed IP addresses/ranges (comma-separated, default: 127.0.0.1,192.168.1.0/24): " ALLOWED_IPS
ALLOWED_IPS=${ALLOWED_IPS:-"127.0.0.1,192.168.1.0/24"}

# ========================
# Installation
# ========================

# Update and install necessary packages
log_message "Updating system and installing required packages..." "📦"
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev

# Install Python libraries
log_message "Installing Python dependencies..." "🐍"
pip3 install Adafruit_DHT Flask

# Create installation directory
API_DIR="/home/$(whoami)/temp_humidity_api"
mkdir -p "$API_DIR"
log_message "Created directory: $API_DIR" "📁"

# Copy API file to installation directory
cp enhanced_temp_humidity_api.py "$API_DIR/enhanced_temp_humidity_api.py"
chmod +x "$API_DIR/enhanced_temp_humidity_api.py"

# Create systemd service file
log_message "Creating systemd service..." "⚙️"
SERVICE_FILE="/tmp/temp_humidity_api.service"

cat <<EOL > "$SERVICE_FILE"
[Unit]
Description=Temperature and Humidity API
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$API_DIR
Environment="TEMP_API_HTTP_PORT=$HTTP_PORT"
EOL

# Add HTTPS configuration to service file if enabled
if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  cat <<EOL >> "$SERVICE_FILE"
Environment="TEMP_API_USE_HTTPS=true"
Environment="TEMP_API_HTTPS_PORT=$HTTPS_PORT"
Environment="TEMP_API_CERT_PATH=$CERT_PATH"
Environment="TEMP_API_KEY_PATH=$KEY_PATH"
EOL

  # Add multi-domain configuration if enabled
  if [[ "${MULTI_DOMAIN,,}" == "y" ]]; then
    cat <<EOL >> "$SERVICE_FILE"
Environment="TEMP_API_MULTI_DOMAIN=true"
EOL

    # Add command-line argument for certificate config file
    CERT_CONFIG_DEST="$API_DIR/certificates.json"
    EXEC_START_CMD="/usr/bin/python3 $API_DIR/enhanced_temp_humidity_api.py --cert-config $CERT_CONFIG_DEST"
  else
    cat <<EOL >> "$SERVICE_FILE"
Environment="TEMP_API_MULTI_DOMAIN=false"
EOL
    EXEC_START_CMD="/usr/bin/python3 $API_DIR/enhanced_temp_humidity_api.py"
  fi
else
  cat <<EOL >> "$SERVICE_FILE"
Environment="TEMP_API_USE_HTTPS=false"
EOL
  EXEC_START_CMD="/usr/bin/python3 $API_DIR/enhanced_temp_humidity_api.py"
fi

# Add security configuration to service file
if [[ "${ENABLE_AUTH,,}" == "y" ]]; then
  cat <<EOL >> "$SERVICE_FILE"
Environment="TEMP_API_REQUIRE_AUTH=true"
Environment="TEMP_API_API_KEY=$API_KEY"
EOL
else
  cat <<EOL >> "$SERVICE_FILE"
Environment="TEMP_API_REQUIRE_AUTH=false"
EOL
fi

cat <<EOL >> "$SERVICE_FILE"
Environment="TEMP_API_ALLOWED_IPS=$ALLOWED_IPS"
ExecStart=${EXEC_START_CMD}
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Install systemd service
sudo mv "$SERVICE_FILE" "/etc/systemd/system/temp_humidity_api.service"
sudo systemctl daemon-reload
sudo systemctl enable temp_humidity_api.service
sudo systemctl start temp_humidity_api.service

# Display service status
log_message "Checking service status..." "🔍"
sudo systemctl status temp_humidity_api.service

# Create a simple configuration summary file
CONFIG_SUMMARY="$API_DIR/api_config.txt"
cat <<EOL > "$CONFIG_SUMMARY"
# Temperature and Humidity API Configuration
# Installed on: $(date)

API HTTP Port: $HTTP_PORT
HTTPS Enabled: ${ENABLE_HTTPS}
EOL

if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  cat <<EOL >> "$CONFIG_SUMMARY"
HTTPS Port: $HTTPS_PORT
EOL

  if [[ "${MULTI_DOMAIN,,}" == "y" ]]; then
    cat <<EOL >> "$CONFIG_SUMMARY"
Multi-Domain Support: Enabled
Default Certificate Path: $CERT_PATH
Default Key Path: $KEY_PATH
Additional Certificates: See $CERT_CONFIG_DEST
EOL
  else
    cat <<EOL >> "$CONFIG_SUMMARY"
Multi-Domain Support: Disabled
Certificate Path: $CERT_PATH
Key Path: $KEY_PATH
EOL
  fi
fi

cat <<EOL >> "$CONFIG_SUMMARY"
Authentication Enabled: ${ENABLE_AUTH}
EOL

if [[ "${ENABLE_AUTH,,}" == "y" ]]; then
  cat <<EOL >> "$CONFIG_SUMMARY"
API Key: $API_KEY
EOL
fi

cat <<EOL >> "$CONFIG_SUMMARY"
Allowed IPs: $ALLOWED_IPS
EOL

log_message "Installation complete!" "✅"
log_message "API service is now running." "🌡️"

# Display access information
if [[ "${ENABLE_HTTPS,,}" == "y" ]]; then
  log_message "🔒 The API is now available via HTTPS:" "🔒"
  log_message "    https://$(hostname -I | awk '{print $1}'):$HTTPS_PORT/metrics" "🌐"
  
  if [[ "${ENABLE_AUTH,,}" == "y" ]]; then
    log_message "    Add the header 'X-API-Key: $API_KEY' to your requests" "🔑"
    log_message "    Or use ?api_key=$API_KEY in the URL" "🔑"
  fi
  
  log_message "Health check URL:" "❤️"
  log_message "    https://$(hostname -I | awk '{print $1}'):$HTTPS_PORT/health" "🌐"
else
  log_message "The API is now available via HTTP:" "🌐"
  log_message "    http://$(hostname -I | awk '{print $1}'):$HTTP_PORT/metrics" "🌐"
  
  if [[ "${ENABLE_AUTH,,}" == "y" ]]; then
    log_message "    Add the header 'X-API-Key: $API_KEY' to your requests" "🔑"
    log_message "    Or use ?api_key=$API_KEY in the URL" "🔑"
  fi
  
  log_message "Health check URL:" "❤️"
  log_message "    http://$(hostname -I | awk '{print $1}'):$HTTP_PORT/health" "🌐"
fi

log_message "Configuration saved to: $CONFIG_SUMMARY" "📋"
