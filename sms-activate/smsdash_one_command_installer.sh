#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# SMSDash One-Command Installer
# - Wires up your Docker app (Node/Express + Telegraf)
# - Creates a simple Dashboard UI served by Nginx
# - Proxies /api to your backend on port 3000
# - Ensures Docker auto-restart (restart: unless-stopped)
# - Adds a /api/health endpoint if missing
#
# USAGE (run as root or via sudo):
#   sudo bash smsdash_one_command_installer.sh <domain> <app_dir>
# Example:
#   sudo bash smsdash_one_command_installer.sh fakew.cyou /home/client_28482_4/scripts/sms-activate
# ----------------------------------------------------------------------------

DOMAIN="${1:-}"
APP_DIR="${2:-}"

if [[ -z "${DOMAIN}" || -z "${APP_DIR}" ]]; then
  echo "\n[!] Usage: sudo bash $0 <domain> <app_dir>\n"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "[!] Please run as root (use sudo)."
  exit 1
fi

WEB_ROOT="/var/www/${DOMAIN}/html"
NGINX_AVAIL="/etc/nginx/sites-available/${DOMAIN}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}"
COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
ENV_FILE="${APP_DIR}/.env"
INDEX_JS="${APP_DIR}/index.js"

# --- Helpers -----------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1; }

echo_step() { echo -e "\n\033[1;36m==> $*\033[0m"; }

echo_ok() { echo -e "\033[1;32m✔ $*\033[0m"; }

echo_warn() { echo -e "\033[1;33m! $*\033[0m"; }

# --- Preflight ---------------------------------------------------------------
echo_step "Checking required commands"
for bin in docker docker-compose nginx; do
  if ! need "$bin"; then
    echo_warn "$bin not found, installing via apt..."
    apt-get update -y
    if [[ "$bin" == "docker" ]]; then
      apt-get install -y docker.io
      systemctl enable --now docker || true
    elif [[ "$bin" == "docker-compose" ]]; then
      apt-get install -y docker-compose
    else
      apt-get install -y nginx
      systemctl enable --now nginx || true
    fi
  fi
  echo_ok "$bin present"
done

# --- Ensure .env exists (do NOT overwrite existing) --------------------------
echo_step "Ensuring ${ENV_FILE} exists"
if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF_ENV'
# --- Minimal env for backend ---
BOT_TOKEN=REPLACE_WITH_YOUR_TELEGRAM_BOT_TOKEN
ADMINS=123456789
SMSACTIVATE_API_KEY=REPLACE_WITH_YOUR_SMS_API_KEY
PORT=3000
SESSION_SECRET=change_me_super_secret
START_LANG=en
BOT_USERNAME=Fake_WA_bot
BASE_URL=http://localhost:3000
PUBLIC_BASE_URL=https://REPLACE_WITH_YOUR_DOMAIN
EOF_ENV
  chown $(stat -c "%U:%G" "${APP_DIR}") "${ENV_FILE}"
  echo_warn "Created ${ENV_FILE}. Update secrets after this script."
else
  echo_ok ".env already present"
fi

# --- Ensure docker-compose has restart policy + sane config -------------------
echo_step "Ensuring docker-compose.yml enforces restart policy"
if [[ -f "${COMPOSE_FILE}" ]]; then
  cp -a "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak.$(date +%s)"
else
  echo_warn "docker-compose.yml not found. Creating a new one."
fi

cat > "${COMPOSE_FILE}" <<EOF_YML
version: "3.9"
services:
  myapp:
    build: .
    container_name: myapp
    ports:
      - "3000:3000"
    env_file:
      - .env
    volumes:
      - ./data:/app/data
    restart: unless-stopped
EOF_YML

chown $(stat -c "%U:%G" "${APP_DIR}") "${COMPOSE_FILE}"

echo_ok "docker-compose.yml written with restart: unless-stopped"

# --- Inject /api/health route if missing -------------------------------------
echo_step "Ensuring /api/health route exists in index.js"
if [[ -f "${INDEX_JS}" ]]; then
  if ! grep -q "app.get('/api/health'" "${INDEX_JS}" 2>/dev/null; then
    cat >> "${INDEX_JS}" <<'EOF_HEALTH'

// --- Auto-inserted health endpoint ---
try {
  if (typeof app !== 'undefined' && app.get) {
    app.get('/api/health', (req, res) => {
      res.json({ ok: true, time: new Date().toISOString() });
    });
    console.log('✔ /api/health endpoint enabled');
  }
} catch (e) {
  console.error('Health endpoint injection failed:', e);
}
EOF_HEALTH
    echo_ok "Inserted /api/health into index.js"
  else
    echo_ok "/api/health already present"
  fi
else
  echo_warn "index.js not found at ${INDEX_JS}. Skipping API health injection."
fi

# --- Create Dashboard UI (static) --------------------------------------------
echo_step "Provisioning dashboard at ${WEB_ROOT}"
mkdir -p "${WEB_ROOT}"
cat > "${WEB_ROOT}/index.html" <<'EOF_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>SMSDash</title>
  <style>
    body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell; margin:0; background:#0b1220; color:#e8eefc; }
    header { padding: 24px; border-bottom: 1px solid #1e2a44; display:flex; align-items:center; justify-content:space-between; }
    .tag { background:#12203a; padding:4px 10px; border-radius:999px; font-size:12px; color:#b7c5e3; }
    main { max-width: 980px; margin: 0 auto; padding: 32px 16px; }
    .card { background:#0f172a; border:1px solid #1e2a44; border-radius:16px; padding:20px; margin-bottom:16px; }
    button { background:#2563eb; color:white; border:none; padding:10px 14px; border-radius:10px; cursor:pointer; }
    button:disabled { background:#334155; cursor:not-allowed; }
    code { background:#0b1220; padding:2px 6px; border-radius:6px; border:1px solid #1e2a44; }
  </style>
</head>
<body>
  <header>
    <div style="display:flex; gap:10px; align-items:center;">
      <div class="tag">SMSDash</div>
      <div id="status" class="tag">Checking...</div>
    </div>
    <a id="tgLink" target="_blank" rel="noreferrer">Open Bot ↗</a>
  </header>

  <main>
    <div class="card">
      <h2>Welcome</h2>
      <p>Your backend is proxied at <code>/api</code>. This dashboard is static and can call your API.</p>
      <p>
        Health: <code id="health">pending...</code>
      </p>
      <div style="margin-top:10px; display:flex; gap:8px;">
        <button id="pingBtn">Ping /api/health</button>
        <button id="buyBtn" disabled>Buy Number (stub)</button>
      </div>
    </div>

    <div class="card">
      <h3>Telegram Login (Widget)</h3>
      <p>Wire this up to create sessions tied to Telegram user IDs.</p>
      <div id="tgWidgetContainer"></div>
    </div>
  </main>

  <script>
    const BOT_USERNAME = 'Fake_WA_bot'; // change if needed
    document.getElementById('tgLink').href = `https://t.me/${BOT_USERNAME}`;

    async function checkHealth(){
      const el = document.getElementById('health');
      try {
        const r = await fetch('/api/health');
        const j = await r.json();
        el.textContent = j.ok ? `ok @ ${j.time}` : 'not ok';
        document.getElementById('pingBtn').disabled = false;
      } catch (e) {
        el.textContent = 'unreachable';
      }
    }

    checkHealth();

    document.getElementById('pingBtn').addEventListener('click', checkHealth);

    // Telegram Login widget injection (replace data-telegram-login)
    const w = document.createElement('script');
    w.async = true;
    w.src = 'https://telegram.org/js/telegram-widget.js?22';
    w.setAttribute('data-telegram-login', BOT_USERNAME); // IMPORTANT
    w.setAttribute('data-size', 'large');
    w.setAttribute('data-userpic', 'false');
    w.setAttribute('data-request-access', 'write');
    w.setAttribute('data-onauth', 'onTelegramAuth(user)');
    document.getElementById('tgWidgetContainer').appendChild(w);

    window.onTelegramAuth = function(user){
      console.log('TG user', user);
      // TODO: send to backend to create a session token
      // fetch('/api/login', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(user) })
    }
  </script>
</body>
</html>
EOF_HTML

chown -R www-data:www-data "/var/www/${DOMAIN}"
chmod -R 755 "/var/www/${DOMAIN}"

echo_ok "Dashboard deployed to https://${DOMAIN}"

# --- Nginx site config (static UI + /api proxy) -------------------------------
echo_step "Writing Nginx site config for ${DOMAIN}"
cat > "${NGINX_AVAIL}" <<EOF_NGX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    root ${WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF_NGX

ln -sf "${NGINX_AVAIL}" "${NGINX_ENABLED}"
nginx -t
systemctl reload nginx

echo_ok "Nginx reloaded. Static UI + /api proxy active."

# --- Build/Run docker app -----------------------------------------------------
echo_step "(Re)building and starting Docker app"
cd "${APP_DIR}"
docker-compose down -v || true
docker-compose up -d --build

echo_ok "Containers are up:" && docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# --- Final checks -------------------------------------------------------------
echo_step "Final health checks"
set +e
curl -fsSLI "http://localhost:3000" >/dev/null && echo_ok "Backend reachable on 3000" || echo_warn "Backend on 3000 not reachable right now"
curl -fsSLI "https://${DOMAIN}" >/dev/null && echo_ok "Dashboard reachable at https://${DOMAIN}" || echo_warn "Dashboard not reachable yet"
set -e

cat <<MSG

All set ✅
- Edit secrets in: ${ENV_FILE}
- Dashboard: https://${DOMAIN}
- Health API: https://${DOMAIN}/api/health
- Compose file: ${COMPOSE_FILE}
- Nginx site: ${NGINX_AVAIL}

If you later need to (re)issue SSL via certbot manually:
  sudo certbot --nginx --cert-name ${DOMAIN} -d ${DOMAIN} -d www.${DOMAIN}

MSG

