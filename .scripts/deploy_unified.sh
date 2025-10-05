#!/usr/bin/env bash
set -e

export REPO_URL="https://github.com/zerken11/ZERKER.git"
export SUBDIR="${1:-sms-activate}"
export EMAIL_ACME="admin@fakew.cyou"
export DOMAIN="${2:-fakew.cyou}"

sudo apt-get update -y
sudo apt-get install -y git curl ufw nginx jq
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm i -g pm2

sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw --force enable

sudo mkdir -p /srv/app && sudo chown -R $USER:$USER /srv/app
cd /srv/app
if [ ! -d repo ]; then git clone "$REPO_URL" repo; fi
cd repo && git pull origin main || true

[ -d "$SUBDIR" ] && cd "$SUBDIR"
APP_ROOT=$(pwd)

BACKEND_DIR=""
FRONTEND_DIR=""
[ -d backend ] && BACKEND_DIR="backend"
[ -d frontend ] && FRONTEND_DIR="frontend"
if [ -z "$BACKEND_DIR" ] && [ -f server.js ]; then BACKEND_DIR="."; fi
if [ -z "$FRONTEND_DIR" ] && [ -f package.json ] && grep -qi '"vite"' package.json; then FRONTEND_DIR="."; fi

APP_NAME=$(basename "$SUBDIR")
echo "Deploying $APP_NAME (backend=$BACKEND_DIR, frontend=$FRONTEND_DIR)"

# --- backend ---
if [ -n "$BACKEND_DIR" ]; then
  cd "$APP_ROOT/$BACKEND_DIR"
  [ -f .env ] || cat > .env <<'ENV'
PORT=4000
JWT_SECRET=change_me_now_please
NODE_ENV=production
ENV
  npm i --omit=dev || true
  mkdir -p data || true

  if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
    echo "🔁 Reloading $APP_NAME..."
    pm2 reload "$APP_NAME"
  else
    echo "🚀 Starting $APP_NAME..."
    if [ -f ecosystem.config.js ]; then
      pm2 start ecosystem.config.js --only "$APP_NAME" || pm2 start ecosystem.config.js
    elif jq -re '.scripts.start' package.json >/dev/null 2>&1; then
      pm2 start npm --name "$APP_NAME" -- start
    elif [ -f server.js ]; then
      pm2 start server.js --name "$APP_NAME"
    else
      echo "⚠️  No valid start file found."
    fi
  fi
fi

# --- frontend ---
if [ -n "$FRONTEND_DIR" ]; then
  cd "$APP_ROOT/$FRONTEND_DIR"
  npm i || true
  if jq -re '.scripts.build' package.json >/dev/null 2>&1; then npm run build; fi
fi

STATIC_ROOT="$APP_ROOT/$FRONTEND_DIR/dist"
[ -d "$STATIC_ROOT" ] || STATIC_ROOT="$APP_ROOT/dist"
[ -d "$STATIC_ROOT" ] || STATIC_ROOT="$APP_ROOT/$FRONTEND_DIR/build"

sudo tee /etc/nginx/sites-available/$DOMAIN >/dev/null <<NGINX
server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN www.$DOMAIN;

  root $STATIC_ROOT;
  index index.html;

  location / { try_files $uri /index.html; }
  location /api/ {
    proxy_pass http://127.0.0.1:4000/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
sudo nginx -t && sudo systemctl reload nginx

sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --redirect -m "$EMAIL_ACME" --agree-tos -n || true

pm2 save
pm2 startup | tail -n 1 | bash

echo "✅ Deployment complete for $APP_NAME → https://$DOMAIN"
