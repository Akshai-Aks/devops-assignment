import os
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)


def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=os.environ.get("DB_PORT", 5432),
        dbname=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "dbadmin"),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=3,
    )


@app.route("/")
def index():
    return jsonify({"status": "ok", "message": "DevOps Assignment App"})


@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/db")
def db_check():
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({"status": "ok", "db": "connected"}), 200
    except Exception as e:
        return jsonify({"status": "error", "db": str(e)}), 500


if __name__ == "__main__":
    port = int(os.environ.get("APP_PORT", 5000))
    app.run(host="0.0.0.0", port=port)

