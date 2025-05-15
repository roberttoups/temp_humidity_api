#!/usr/bin/env python3

import requests
import csv
from datetime import datetime
import os
import ssl
import argparse

# Default URIs
HTTP_URI = "http://localhost:8000/metrics"
HTTPS_URI = "https://localhost/metrics"


def fetch_data(uri, verify=True):
    """Make an HTTP/HTTPS GET request to the specified URI and return the JSON response.
    
    Args:
        uri (str): The URI to fetch data from
        verify (bool): Whether to verify SSL certificates (set to False for self-signed certs)
        
    Returns:
        dict: The JSON response from the API
    """
    try:
        response = requests.get(uri, verify=verify)
        response.raise_for_status()  # This will raise an exception for HTTP errors
        return response.json()
    except requests.exceptions.SSLError as e:
        print(f"❌ SSL Error: {e}")
        print("If using self-signed certificates, try using --no-verify option")
        raise
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Connection Error: {e}")
        raise
    except Exception as e:
        print(f"❌ Error fetching data: {e}")
        raise


def append_to_csv(data, filename, subdirectory):
    """Append the data as a new row in the CSV file. Create the file if it doesn't exist."""
    # Ensure the subdirectory exists
    os.makedirs(subdirectory, exist_ok=True)

    # Construct the full file path
    filepath = os.path.join(subdirectory, filename)

    with open(filepath, "a", newline="") as csvfile:
        # Add timestamp to the data dictionary
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        data_with_timestamp = {"timestamp": timestamp, **data}

        fieldnames = [
            "timestamp",
            "humidity",
            "temperature_celsius",
            "temperature_fahrenheit",
        ]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        # Check if the file is empty to write the header
        csvfile.seek(0, 2)  # Move to the end of the file
        if csvfile.tell() == 0:  # Check if the file is empty
            writer.writeheader()  # Write header only if the file is empty

        writer.writerow(data_with_timestamp)


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='Fetch temperature and humidity data and save to CSV.')
    parser.add_argument('--protocol', choices=['http', 'https'], default='https',
                       help='Protocol to use (http or https, default: https)')
    parser.add_argument('--host', default='localhost',
                       help='Hostname to connect to (default: localhost)')
    parser.add_argument('--port', type=int,
                       help='Port to connect to (default: 8000 for HTTP, 443 for HTTPS)')
    parser.add_argument('--path', default='/metrics',
                       help='API endpoint path (default: /metrics)')
    parser.add_argument('--no-verify', action='store_true',
                       help='Disable SSL certificate verification (for self-signed certs)')
    parser.add_argument('--subdirectory', default='temperature_data',
                       help='Subdirectory to save data in (default: temperature_data)')
    
    return parser.parse_args()


def main():
    # Parse command line arguments
    args = parse_arguments()
    
    # Determine port if not specified
    if not args.port:
        args.port = 8000 if args.protocol == 'http' else 443
    
    # Build the URI
    uri = f"{args.protocol}://{args.host}:{args.port}{args.path}"
    
    print(f"📋 Fetching data from: {uri}")
    
    try:
        # Fetch data from the API
        data = fetch_data(uri, verify=not args.no_verify)

        # Generate the filename with a timestamp
        timestamp = datetime.now().strftime("%Y%m%d")
        filename = f"{timestamp}.csv"

        # Append the data to the CSV file within the subdirectory
        append_to_csv(data, filename, args.subdirectory)
        print(f"✅ Data appended to {os.path.join(args.subdirectory, filename)}")
    except Exception as e:
        print(f"❌ Failed to process data: {e}")
        exit(1)


if __name__ == "__main__":
    main()
