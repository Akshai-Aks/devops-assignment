import os
import time
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, jsonify, request, render_template

app = Flask(__name__)

_cw = None

def get_cloudwatch():
    global _cw
    if _cw is None:
        _cw = boto3.client("cloudwatch", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    return _cw

def put_metrics(path, latency_ms, status_code):
    try:
        is_error = 1 if status_code >= 400 else 0
        get_cloudwatch().put_metric_data(
            Namespace="devops-assignment/App",
            MetricData=[
                # per-endpoint breakdown
                {"MetricName": "RequestCount", "Dimensions": [{"Name": "Endpoint", "Value": path}], "Value": 1, "Unit": "Count"},
                {"MetricName": "Latency",      "Dimensions": [{"Name": "Endpoint", "Value": path}], "Value": latency_ms, "Unit": "Milliseconds"},
                {"MetricName": "ErrorCount",   "Dimensions": [{"Name": "Endpoint", "Value": path}], "Value": is_error, "Unit": "Count"},
                # aggregate (no dimensions) — needed for dashboard total widgets
                {"MetricName": "RequestCount", "Dimensions": [], "Value": 1, "Unit": "Count"},
                {"MetricName": "Latency",      "Dimensions": [], "Value": latency_ms, "Unit": "Milliseconds"},
                {"MetricName": "ErrorCount",   "Dimensions": [], "Value": is_error, "Unit": "Count"},
            ],
        )
    except Exception:
        pass  # never let metrics failures affect the response


@app.before_request
def start_timer():
    request._start_time = time.time()


@app.after_request
def record_metrics(response):
    if hasattr(request, "_start_time"):
        latency_ms = (time.time() - request._start_time) * 1000
        put_metrics(request.path, latency_ms, response.status_code)
    return response


def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=os.environ.get("DB_PORT", 5432),
        dbname=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "dbadmin"),
        password=os.environ.get("DB_PASSWORD", ""),
        connect_timeout=3,
    )


def init_db():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id         SERIAL PRIMARY KEY,
            name       VARCHAR(100) NOT NULL,
            email      VARCHAR(150) UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    cur.close()
    conn.close()


@app.route("/")
def index():
    return render_template("index.html")


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


@app.route("/users", methods=["GET"])
def get_users():
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT id, name, email, created_at FROM users ORDER BY created_at DESC")
        users = [dict(u) for u in cur.fetchall()]
        cur.close()
        conn.close()
        return jsonify({"users": users}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/users", methods=["POST"])
def create_user():
    data = request.get_json()
    if not data or not data.get("name") or not data.get("email"):
        return jsonify({"error": "name and email are required"}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            "INSERT INTO users (name, email) VALUES (%s, %s) RETURNING id, name, email, created_at",
            (data["name"], data["email"]),
        )
        user = dict(cur.fetchone())
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({"user": user}), 201
    except psycopg2.errors.UniqueViolation:
        return jsonify({"error": "email already exists"}), 409
    except Exception as e:
        return jsonify({"error": str(e)}), 500


try:
    init_db()
except Exception:
    pass  # DB may not be available at startup in test environments

if __name__ == "__main__":
    port = int(os.environ.get("APP_PORT", 5000))
    app.run(host="0.0.0.0", port=port)
