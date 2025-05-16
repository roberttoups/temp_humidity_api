# Enhanced Temperature and Humidity API with HTTPS Support

This document explains the enhanced version of the Temperature and Humidity API that includes built-in HTTPS support and additional security features.

## 📝 Overview

The enhanced API offers several improvements over the original implementation:

1. **Built-in HTTPS support** - No need for Nginx as a reverse proxy
2. **Authentication** - API key-based authentication for secure access
3. **IP filtering** - Restrict access to specific IP addresses/ranges
4. **Configuration flexibility** - Support for environment variables, command-line arguments, and config files
5. **Health endpoint** - Simple health check endpoint for monitoring
6. **Security headers** - Proper security headers for improved security
7. **Comprehensive logging** - Better logging for troubleshooting

## 📋 Installation

1. **Use the enhanced installation script**:

   ```bash
   chmod +x install_enhanced_api.sh
   ./install_enhanced_api.sh
   ```

   The script will prompt for configuration options and set up the API as a systemd service.

### Manual Configuration for Multiple Domains

If you prefer to configure multi-domain support manually:

1. Create a certificate configuration JSON file:

   ```bash
   cat <<EOL > certificates.json
   {
     "raspberry.local": {
       "cert_path": "/etc/letsencrypt/live/raspberry.local/fullchain.pem",
       "key_path": "/etc/letsencrypt/live/raspberry.local/privkey.pem"
     },
     "raspberry.tailnet-name.ts.net": {
       "cert_path": "/var/lib/tailscale/certs/raspberry/cert.pem",
       "key_path": "/var/lib/tailscale/certs/raspberry/key.pem"
     }
   }
   EOL
   ```

2. Run the API with multi-domain support:

   ```bash
   python3 enhanced_temp_humidity_api.py --multi-domain --cert-config certificates.json
   ```

## 🔐 Security Features

### API Key Authentication

The enhanced API supports API key authentication. You can provide the API key in two ways:

1. **HTTP header**: Add the `X-API-Key` header to your requests:

   ```bash
   curl -H "X-API-Key: your_api_key" https://your_pi:8443/metrics
   ```

2. **Query parameter**: Add the API key as a query parameter:

   ```bash
   curl https://your_pi:8443/metrics?api_key=your_api_key
   ```

### IP Filtering

The API can restrict access to specific IP addresses or IP ranges. Configure this during installation or via environment variables.

### HTTPS Configuration

The API supports direct HTTPS configuration, including:

- Custom HTTPS port (default: 8443)
- Certificate and key path configuration
- Option to fall back to HTTP if certificates are not available
- **Multi-domain support with SNI** - Serve different certificates for different domain names

#### Multi-domain Certificate Configuration

The enhanced API supports Server Name Indication (SNI), allowing it to serve different certificates for different domain names. This is particularly useful if you access your Raspberry Pi using multiple domains (e.g., local IP, hostname, and Tailscale domain).

To configure multiple certificates, you have several options:

1. **Use the Enhanced Installation Script**
   - The script will prompt you to configure multiple domains
   - You'll be asked for each domain name and its certificate paths

2. **Use a JSON Configuration File**
   - Create a JSON file with the following structure:

   ```json
   {
     "example.com": {
       "cert_path": "/path/to/example.com/cert.pem",
       "key_path": "/path/to/example.com/key.pem"
     },
     "raspberry.local": {
       "cert_path": "/path/to/raspberry.local/cert.pem",
       "key_path": "/path/to/raspberry.local/key.pem"
     },
     "*.wildcard-domain.com": {
       "cert_path": "/path/to/wildcard/cert.pem",
       "key_path": "/path/to/wildcard/key.pem"
     }
   }
   ```

   - Pass this file to the API with `--cert-config /path/to/certificates.json`

3. **Use Environment Variables**
   - For each domain, set an environment variable:

   ```bash
   export TEMP_API_CERTIFICATE_example.com=/path/to/example.com/cert.pem,/path/to/example.com/key.pem
   export TEMP_API_CERTIFICATE_raspberry.local=/path/to/raspberry.local/cert.pem,/path/to/raspberry.local/key.pem
   ```

   - Also set `TEMP_API_MULTI_DOMAIN=true`

## 🔧 Configuration Options

### Environment Variables

All settings can be configured using environment variables:

| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| `TEMP_API_HTTP_PORT` | HTTP port | 5000 |
| `TEMP_API_HTTPS_PORT` | HTTPS port | 8443 |
| `TEMP_API_USE_HTTPS` | Enable HTTPS | true |
| `TEMP_API_CERT_PATH` | Path to SSL certificate | */etc/letsencrypt/live/hostname/fullchain.pem* |
| `TEMP_API_KEY_PATH` | Path to SSL key | */etc/letsencrypt/live/hostname/privkey.pem* |
| `TEMP_API_REQUIRE_AUTH` | Require authentication | true |
| `TEMP_API_API_KEY` | API key | *generated during installation* |
| `TEMP_API_ALLOWED_IPS` | Allowed IP addresses/ranges | 127.0.0.1,192.168.1.0/24 |
| `TEMP_API_MULTI_DOMAIN` | Enable multi-domain support | false |
| `TEMP_API_CERTIFICATES` | JSON string with certificate configurations | {} |
| `TEMP_API_CERTIFICATE_domain.com` | Certificate and key paths for a domain (format: cert_path,key_path) | |

### Command-Line Arguments

The API supports the following command-line arguments:

```bash
python3 enhanced_temp_humidity_api.py --help
```

```
usage: enhanced_temp_humidity_api.py [-h] [--http-port HTTP_PORT] [--https-port HTTPS_PORT] 
                                     [--use-https] [--no-https] [--cert CERT] [--key KEY]
                                     [--require-auth] [--no-auth] [--api-key API_KEY]
                                     [--allowed-ips ALLOWED_IPS] [--multi-domain]
                                     [--cert-config CERT_CONFIG]

Temperature and Humidity API with HTTPS support

optional arguments:
  -h, --help            show this help message and exit
  --http-port HTTP_PORT HTTP port (default: 5000)
  --https-port HTTPS_PORT HTTPS port (default: 8443)
  --use-https          Enable HTTPS
  --no-https           Disable HTTPS
  --cert CERT          Path to SSL certificate
  --key KEY            Path to SSL private key
  --require-auth       Require API key authentication
  --no-auth            Disable authentication
  --api-key API_KEY    API key for authentication
  --allowed-ips ALLOWED_IPS Comma-separated list of allowed IP addresses/ranges
  --multi-domain       Enable multi-domain support with SNI
  --cert-config CERT_CONFIG Path to JSON file containing certificate configurations
```

## 🔗 API Endpoints

### GET /metrics

Returns temperature and humidity data.

**Response example**:

```json
{
  "timestamp": "2023-05-14T15:32:45.123456",
  "temperature_celsius": 21.9,
  "temperature_fahrenheit": 71.42,
  "humidity": 52.4
}
```

### GET /health

Health check endpoint that doesn't require authentication.

**Response example**:

```json
{
  "status": "healthy",
  "timestamp": "2023-05-14T15:32:45.123456"
}
```

## 📊 Data Collection

Use the enhanced data collection script for local data storage:

```bash
python3 enhanced_get_local_data.py --protocol https --host localhost --port 8443 --api-key your_api_key
```

### Command-Line Options

```
usage: enhanced_get_local_data.py [-h] [--protocol {http,https}] [--host HOST] 
                                 [--port PORT] [--path PATH] [--no-verify]
                                 [--subdirectory SUBDIRECTORY] [--api-key API_KEY]
                                 [--config-file CONFIG_FILE]

Fetch temperature and humidity data from the API and store locally

optional arguments:
  -h, --help            show this help message and exit
  --protocol {http,https} Protocol to use (http or https, default: https)
  --host HOST           Hostname to connect to (default: localhost)
  --port PORT           Port to connect to (default: 8443 for HTTPS, 5000 for HTTP)
  --path PATH           API endpoint path (default: /metrics)
  --no-verify           Disable SSL certificate verification (for self-signed certs)
  --subdirectory SUBDIRECTORY Subdirectory to save data in (default: temperature_data)
  --api-key API_KEY     API key for authentication
  --config-file CONFIG_FILE Path to a JSON configuration file
```

### JSON Configuration

You can also use a JSON configuration file:

```json
{
  "protocol": "https",
  "host": "localhost",
  "port": 8443,
  "path": "/metrics",
  "verify": true,
  "subdirectory": "temperature_data",
  "api_key": "your_api_key"
}
```

## 📆 Cron Job Examples

### For HTTPS with API Key Authentication

```bash
*/5 * * * * /usr/bin/python3 /home/pi/temp_humidity_api/enhanced_get_local_data.py --api-key YOUR_API_KEY
```

### For Self-Signed Certificates

```bash
*/5 * * * * /usr/bin/python3 /home/pi/temp_humidity_api/enhanced_get_local_data.py --no-verify --api-key YOUR_API_KEY
```

### Using a Configuration File

```bash
*/5 * * * * /usr/bin/python3 /home/pi/temp_humidity_api/enhanced_get_local_data.py --config-file /home/pi/temp_humidity_api/config.json
```
