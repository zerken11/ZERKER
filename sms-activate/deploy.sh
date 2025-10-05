#!/usr/bin/env bash
set -euo pipefail

# === Config ===
APP_DIR="/home/client_28482_4/ZERKER/sms-activate"

echo "[+] Changing to application directory: $APP_DIR"
cd "$APP_DIR"

echo "[+] Pulling latest code from Git..."
git pull --ff-only

echo "[+] Installing production dependencies..."
npm install --omit=dev

echo "[+] Restarting pm2 process..."
pm2 restart sms-activate

echo "🚀 Deployment complete."

