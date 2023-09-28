from flask import Flask, jsonify
import Adafruit_DHT

app = Flask(__name__)

SENSOR = Adafruit_DHT.DHT22
PIN = 4  # GPIO4


@app.route("/metrics", methods=["GET"])
def get_metrics():
    humidity, temperature = Adafruit_DHT.read_retry(SENSOR, PIN)

    if humidity is not None and temperature is not None:
        temperature_fahrenheit = (temperature * 9 / 5) + 32
        return jsonify(
            {
                "temperature_celsius": temperature,
                "temperature_fahrenheit": temperature_fahrenheit,
                "humidity": humidity,
            }
        )
    else:
        return jsonify({"error": "Failed to get reading from the sensor"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
