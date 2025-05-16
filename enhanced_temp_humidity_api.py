#!/usr/bin/env python3
# filepath: /Users/toups/Dropbox/git/temp_humidity_api/enhanced_temp_humidity_api.py

import os
import logging
import ssl
import json
from datetime import datetime
import argparse
from functools import wraps
import Adafruit_DHT
from flask import Flask, jsonify, request, Response

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("temp_humidity_api")

# Initialize Flask app
app = Flask(__name__)

# Sensor configuration
SENSOR = Adafruit_DHT.DHT22
PIN = 4  # GPIO4

# Default configuration (can be overridden by environment variables or CLI args)
DEFAULT_CONFIG = {
    "http_port": 5000,
    "https_port": 8443,
    "use_https": True,
    "cert_path": "/etc/letsencrypt/live/$(hostname)/fullchain.pem",
    "key_path": "/etc/letsencrypt/live/$(hostname)/privkey.pem",
    "require_auth": True,
    "api_key": "change_this_to_a_secure_key",
    "allowed_ips": ["127.0.0.1", "192.168.1.0/24"],
    # Added support for multiple certificates
    "multi_domain": False,
    "certificates": {}
}

# Load configuration from environment variables
config = DEFAULT_CONFIG.copy()
for key in config:
    env_key = f"TEMP_API_{key.upper()}"
    if env_key in os.environ:
        # Handle boolean values
        if isinstance(config[key], bool):
            config[key] = os.environ[env_key].lower() in ("true", "yes", "1")
        # Handle lists
        elif isinstance(config[key], list):
            config[key] = os.environ[env_key].split(",")
        # Handle dictionary for certificates
        elif key == "certificates" and env_key in os.environ:
            try:
                config[key] = json.loads(os.environ[env_key])
            except json.JSONDecodeError:
                logger.error(f"Failed to parse certificates JSON from environment variable")
        else:
            config[key] = os.environ[env_key]

# Load certificates from environment variables if specified in format:
# TEMP_API_CERTIFICATE_domain.com=/path/to/cert.pem,/path/to/key.pem
for env_key, value in os.environ.items():
    if env_key.startswith("TEMP_API_CERTIFICATE_"):
        domain = env_key[len("TEMP_API_CERTIFICATE_"):]
        try:
            cert_path, key_path = value.split(",")
            config["certificates"][domain] = {
                "cert_path": cert_path,
                "key_path": key_path
            }
            config["multi_domain"] = True
        except ValueError:
            logger.error(f"Invalid certificate format for {domain}. Expected 'cert_path,key_path'")


def is_ip_allowed(ip_addr):
    """Check if an IP address is in the allowed list, including subnet support."""
    if not config["allowed_ips"]:
        return True
    
    # Simple matching for exact IPs
    if ip_addr in config["allowed_ips"]:
        return True
    
    # For advanced IP range validation, you'd need to use a library like netaddr
    # This is a simplification; in production use a proper IP validation library
    for allowed in config["allowed_ips"]:
        if "/" in allowed:  # Very basic CIDR check - not comprehensive!
            network_part = allowed.split("/")[0]
            if ip_addr.startswith(network_part.rsplit(".", 1)[0]):
                return True
    
    return False


def check_auth(request):
    """Check if a request is authenticated using either API key or IP."""
    # Always check IP restrictions if they exist
    client_ip = request.remote_addr
    if not is_ip_allowed(client_ip):
        logger.warning(f"Request from unauthorized IP: {client_ip}")
        return False

    # If authentication is not required, IP check is enough
    if not config["require_auth"]:
        return True
    
    # Check for API key in headers or query parameters
    api_key = request.headers.get("X-API-Key") or request.args.get("api_key")
    if api_key == config["api_key"]:
        return True
    
    logger.warning(f"Invalid or missing API key from IP: {client_ip}")
    return False


def requires_auth(f):
    """Decorator to require authentication for an endpoint."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not check_auth(request):
            return Response(
                '{"error": "Authentication required"}',
                status=401,
                mimetype="application/json",
            )
        return f(*args, **kwargs)
    return decorated


@app.route("/metrics", methods=["GET"])
@requires_auth
def get_metrics():
    """Endpoint to get temperature and humidity metrics."""
    try:
        humidity, temperature = Adafruit_DHT.read_retry(SENSOR, PIN)
        
        if humidity is not None and temperature is not None:
            temperature_fahrenheit = (temperature * 9 / 5) + 32
            data = {
                "timestamp": datetime.now().isoformat(),
                "temperature_celsius": temperature,
                "temperature_fahrenheit": temperature_fahrenheit,
                "humidity": humidity,
            }
            logger.info(f"Sensor data read successfully: {data}")
            return jsonify(data)
        else:
            logger.error("Failed to get reading from sensor")
            return jsonify({"error": "Failed to get reading from the sensor"}), 500
    except Exception as e:
        logger.exception(f"Error reading sensor data: {str(e)}")
        return jsonify({"error": f"Sensor read error: {str(e)}"}), 500


@app.route("/health", methods=["GET"])
def health_check():
    """A simple health check endpoint that doesn't require authentication."""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Temperature and Humidity API with HTTPS support")
    parser.add_argument("--http-port", type=int, help=f"HTTP port (default: {config['http_port']})")
    parser.add_argument("--https-port", type=int, help=f"HTTPS port (default: {config['https_port']})")
    parser.add_argument("--use-https", action="store_true", help="Enable HTTPS")
    parser.add_argument("--no-https", action="store_false", dest="use_https", help="Disable HTTPS")
    parser.add_argument("--cert", help=f"Path to SSL certificate (default: {config['cert_path']})")
    parser.add_argument("--key", help=f"Path to SSL private key (default: {config['key_path']})")
    parser.add_argument("--require-auth", action="store_true", help="Require API key authentication")
    parser.add_argument("--no-auth", action="store_false", dest="require_auth", help="Disable authentication")
    parser.add_argument("--api-key", help="API key for authentication")
    parser.add_argument("--allowed-ips", help="Comma-separated list of allowed IP addresses/ranges")
    parser.add_argument("--multi-domain", action="store_true", help="Enable multi-domain support with SNI")
    parser.add_argument("--cert-config", help="Path to JSON file containing certificate configurations")
    
    args = parser.parse_args()
    
    # Update config with command-line arguments if provided
    if args.http_port:
        config["http_port"] = args.http_port
    if args.https_port:
        config["https_port"] = args.https_port
    if args.use_https is not None:
        config["use_https"] = args.use_https
    if args.cert:
        config["cert_path"] = args.cert
    if args.key:
        config["key_path"] = args.key
    if args.require_auth is not None:
        config["require_auth"] = args.require_auth
    if args.api_key:
        config["api_key"] = args.api_key
    if args.allowed_ips:
        config["allowed_ips"] = args.allowed_ips.split(",")
    if args.multi_domain is not None:
        config["multi_domain"] = args.multi_domain
    
    # Load certificate configuration from JSON file if provided
    if args.cert_config and os.path.exists(args.cert_config):
        try:
            with open(args.cert_config, 'r') as f:
                cert_config = json.load(f)
                config["certificates"].update(cert_config)
                config["multi_domain"] = True
                logger.info(f"Loaded certificates for domains: {', '.join(cert_config.keys())}")
        except Exception as e:
            logger.error(f"Failed to load certificate configuration: {e}")
    
    return args


def create_ssl_context():
    """Create an SSL context with support for multiple certificates via SNI."""
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    
    # If multi-domain is enabled and we have certificates configured
    if config["multi_domain"] and config["certificates"]:
        logger.info(f"Configuring multi-domain SSL with {len(config['certificates'])} certificates")
        
        # Create the SNI context selector
        sni_callback = get_sni_callback(config["certificates"])
        context.sni_callback = sni_callback
        
        # Add the default certificate if it exists
        if os.path.exists(config["cert_path"]) and os.path.exists(config["key_path"]):
            context.load_cert_chain(config["cert_path"], config["key_path"])
            logger.info(f"Loaded default certificate from {config['cert_path']}")
    else:
        # Regular single certificate mode
        context.load_cert_chain(config["cert_path"], config["key_path"])
        logger.info(f"Loaded certificate from {config['cert_path']}")
    
    # Set modern secure protocols and ciphers
    context.options |= ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1
    context.set_ciphers('ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256')
    
    return context


def get_sni_callback(certificates):
    """
    Create and return an SNI callback function for the SSL context.
    
    Args:
        certificates: Dictionary mapping domain names to certificate/key paths
        
    Returns:
        function: SNI callback function
    """
    def sni_callback(ssl_sock, server_name, ssl_ctx):
        """SNI callback to load the appropriate certificate for the requested domain."""
        if not server_name:
            logger.warning("No SNI server_name, using default certificate")
            return
        
        logger.info(f"SNI request for domain: {server_name}")
        
        # Check if we have a certificate for this domain
        domain = server_name.decode() if isinstance(server_name, bytes) else server_name
        
        # Try to find a matching certificate (exact match or wildcard)
        cert_info = None
        for cert_domain, info in certificates.items():
            if cert_domain == domain or (cert_domain.startswith('*.') and domain.endswith(cert_domain[1:])):
                cert_info = info
                logger.info(f"Found matching certificate for {domain} with pattern {cert_domain}")
                break
        
        if cert_info and os.path.exists(cert_info["cert_path"]) and os.path.exists(cert_info["key_path"]):
            try:
                logger.info(f"Loading certificate for {domain}: {cert_info['cert_path']}")
                ssl_sock.load_cert_chain(cert_info["cert_path"], cert_info["key_path"])
            except Exception as e:
                logger.error(f"Error loading certificate for {domain}: {e}")
        else:
            logger.warning(f"No certificate found for {domain}, using default")
    
    return sni_callback


def main():
    """Run the Flask application with the appropriate configuration."""
    parse_args()
    
    # Set security headers
    @app.after_request
    def add_security_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response
    
    logger.info(f"Starting Temperature and Humidity API")
    logger.info(f"HTTP enabled on port {config['http_port']}")
    
    if config["use_https"]:
        # Default certificates
        default_cert_exists = os.path.exists(config["cert_path"]) and os.path.exists(config["key_path"])
        
        # Check for at least one valid certificate configuration
        multi_domain_certs_valid = False
        if config["multi_domain"] and config["certificates"]:
            for domain, cert_info in config["certificates"].items():
                if os.path.exists(cert_info["cert_path"]) and os.path.exists(cert_info["key_path"]):
                    multi_domain_certs_valid = True
                    break
        
        if not default_cert_exists and not multi_domain_certs_valid:
            logger.error(f"No valid SSL certificates found. Check your certificate configurations.")
            logger.info("Falling back to HTTP only")
            app.run(host="0.0.0.0", port=config["http_port"])
        else:
            try:
                # Create SSL context with SNI support if needed
                ssl_context = create_ssl_context()
                logger.info(f"HTTPS enabled on port {config['https_port']}")
                
                domains = list(config["certificates"].keys()) if config["multi_domain"] else ["default"]
                logger.info(f"Serving HTTPS for domains: {', '.join(domains)}")
                
                app.run(host="0.0.0.0", port=config["https_port"], ssl_context=ssl_context)
            except Exception as e:
                logger.error(f"Failed to start HTTPS server: {e}")
                logger.info("Falling back to HTTP only")
                app.run(host="0.0.0.0", port=config["http_port"])
    else:
        app.run(host="0.0.0.0", port=config["http_port"])


if __name__ == "__main__":
    main()
