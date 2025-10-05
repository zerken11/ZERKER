#!/bin/bash
set -e

cd /home/client_28482_4/scripts/sms-activate

echo "=== Writing Dockerfile (Node 18 LTS) ==="
cat > Dockerfile <<'EOF'
FROM node:18-alpine

WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
EOF

echo "=== Writing docker-compose.yml ==="
cat > docker-compose.yml <<'EOF'
version: '3.8'
services:
  myapp:
    build: .
    container_name: myapp
    restart: unless-stopped
    ports:
      - "3000:3000"
    env_file:
      - .env
EOF

echo "=== Stopping old containers and cleaning up ==="
docker-compose down -v || true
docker system prune -af || true

echo "=== Building and starting with Node 18 ==="
docker-compose up -d --build

echo "=== Waiting for container to boot... ==="
sleep 5

echo "=== Checking health endpoint ==="
curl -sS http://localhost:3000/api/health || echo "⚠️ Backend not responding yet, check logs with: docker logs -f myapp"

