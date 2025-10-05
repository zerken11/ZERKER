#!/usr/bin/env bash
set -euo pipefail

# === Config ===
APP_DIR="/home/client_28482_4/scripts/sms-activate"
WEB_ROOT="/var/www/fakew.cyou/html"
DOMAIN="fakew.cyou"

# === 1. Update repo / app ===
cd "$APP_DIR"
echo "[+] Building Docker container for app..."
sudo docker-compose down -v || true
sudo docker-compose up -d --build

# === 2. Build frontend (if React/Vite exists) ===
if [ -f package.json ] && grep -q "vite" package.json; then
  echo "[+] Building frontend with Vite..."
  npm install --legacy-peer-deps
  npm run build
  sudo mkdir -p "$WEB_ROOT"
  sudo cp -r dist/* "$WEB_ROOT"/
fi

# === 3. Nginx config ===
CONF_PATH="/etc/nginx/sites-available/$DOMAIN"
sudo tee "$CONF_PATH" >/dev/null <<CONF
server {
    server_name $DOMAIN www.$DOMAIN;

    root $WEB_ROOT;
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
CONF

sudo ln -sf "$CONF_PATH" /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# === 4. Certbot SSL ===
echo "[+] Ensuring SSL certs..."
sudo certbot --nginx --non-interactive --agree-tos -m admin@$DOMAIN -d $DOMAIN -d www.$DOMAIN || true

# === 5. Auto-restart docker ===
echo "[+] Enabling Docker restart on reboot..."
sudo systemctl enable docker || true

# === Done ===
echo "🚀 Deployment complete: https://$DOMAIN"

