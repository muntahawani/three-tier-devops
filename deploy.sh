#!/bin/bash
set -e

echo "=== STAGE 1: Creating 3-Tier Application Files ==="
mkdir -p backend frontend

# 1. Create Backend files
cat << 'EOF' > backend/requirements.txt
Flask==3.0.3
redis==5.0.4
requests==2.31.0
EOF

cat << 'EOF' > backend/app.py
import os
from flask import Flask, jsonify
import redis

app = Flask(__name__)
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
    return jsonify({"tier": "Tier 2 (Flask API)", "database_status": db_status, "views_counter": views}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat << 'EOF' > backend/test_app.py
import unittest
from app import app

class BackendTestCase(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True

    def test_health_check(self):
        response = self.app.get('/health')
        self.assertEqual(response.status_code, 200)

    def test_api_route(self):
        response = self.app.get('/api/data')
        self.assertEqual(response.status_code, 200)

if __name__ == '__main__':
    unittest.main()
EOF

cat << 'EOF' > backend/Dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

# 2. Create Frontend files
cat << 'EOF' > frontend/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>3-Tier App</title>
  <style>
    body { font-family: sans-serif; background: #0f172a; color: white; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
    .card { background: #1e293b; padding: 2rem; border-radius: 8px; text-align: center; width: 350px; }
    .box { background: #334155; padding: 8px; margin: 8px 0; border-radius: 4px; }
  </style>
</head>
<body>
  <div class="card">
    <h2>3-Tier Deployment Live</h2>
    <div class="box">Tier 1 (DB): <span id="db">Connecting...</span></div>
    <div class="box">Tier 2 (API Hits): <span id="hits">0</span></div>
    <div class="box">Tier 3 (UI): Port 8085</div>
  </div>
  <script>
    fetch('http://' + window.location.hostname + ':5001/api/data')
      .then(res => res.json())
      .then(data => {
        document.getElementById('db').innerText = data.database_status;
        document.getElementById('hits').innerText = data.views_counter;
      })
      .catch(() => { document.getElementById('db').innerText = "API Offline"; });
  </script>
</body>
</html>
EOF

cat << 'EOF' > frontend/Dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

echo "=== STAGE 2: Automated Testing (CI) ==="
# Install test dependencies directly in test phase and execute unit tests
pip install --break-system-packages Flask==3.0.3 redis==5.0.4 || pip install Flask==3.0.3 redis==5.0.4 || true
python3 backend/test_app.py

echo "=== STAGE 3: Network & Old Container Cleanup ==="
docker network inspect three-tier-net >/dev/null 2>&1 || docker network create three-tier-net
docker stop frontend-tier backend-tier db-tier || true
docker rm -f frontend-tier backend-tier db-tier || true

echo "=== STAGE 4: Build & Deploy 3-Tier Stack ==="
# Tier 1: Redis
docker run -d --name db-tier --network three-tier-net redis:alpine

# Tier 2: Backend API (Build + Run on internal network and expose 5001 for browser)
docker build -t three-tier-backend:latest ./backend
docker run -d --name backend-tier --network three-tier-net -p 5001:5000 three-tier-backend:latest

# Tier 3: Frontend Web (Build + Run on port 8085)
docker build -t three-tier-frontend:latest ./frontend
docker run -d --name frontend-tier --network three-tier-net -p 8085:80 three-tier-frontend:latest

echo "=== STAGE 5: Deployment Verification ==="
sleep 4
docker ps --filter "name=-tier"
echo "Deployment successful! Open http://localhost:8085 in your browser."