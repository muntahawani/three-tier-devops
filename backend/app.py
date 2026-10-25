import os
from flask import Flask, jsonify
import redis

app = Flask(__name__)

# Reads the DB host from environment variable, defaults to 'db-tier' (service/container name)
DB_HOST = os.getenv("DB_HOST", "db-tier")
DB_PORT = int(os.getenv("DB_PORT", 6379))

def get_redis_client():
    return redis.Redis(host=DB_HOST, port=DB_PORT, socket_connect_timeout=2, decode_responses=True)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "service": "backend-api"}), 200

@app.route('/api/data', methods=['GET'])
def get_data():
    try:
        r = get_redis_client()
        views = r.incr("page_views")
        db_status = "Connected to Redis"
    except Exception as e:
        views = "Unavailable"
        db_status = f"Database unreachable: {str(e)}"

    return jsonify({
        "tier": "Tier 2 (Flask API)",
        "database_status": db_status,
        "views_counter": views
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)