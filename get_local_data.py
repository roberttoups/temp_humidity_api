#!/usr/bin/env python3

import requests
import csv
from datetime import datetime
import os

# Fixed URI
URI = "http://localhost:8000/metrics"


def fetch_data():
    """Make an HTTP GET request to the specified URI and return the JSON response."""
    response = requests.get(URI)
    response.raise_for_status()  # This will raise an exception for HTTP errors
    return response.json()


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


def main():
    # Fetch data from the API
    data = fetch_data()

    # Generate the filename with a timestamp
    timestamp = datetime.now().strftime("%Y%m%d")
    filename = f"{timestamp}.csv"

    # Define the subdirectory
    subdirectory = "temperature_data"

    # Append the data to the CSV file within the subdirectory
    append_to_csv(data, filename, subdirectory)
    print(f"Data appended to {os.path.join(subdirectory, filename)}")


if __name__ == "__main__":
    main()
