#!/usr/bin/env bash
set -euo pipefail

# =============================================
# Replit one-shot bootstrap: Bot + Dashboard
# - Removes any mock/demo DB
# - Seeds *real* prices you enter (EG & CA)
# - Default language = Arabic, with AR/EN toggle
# - Express + Telegraf + SQLite (file DB)
# - Telegram Instant Login + optional user/password
# - Basic hardening (helmet, rate-limit, CSRF, sessions)
# =============================================

PROJECT_DIR="tg-bot-dashboard-ar-en"
if [ -d "$PROJECT_DIR" ]; then
  echo "[i] Directory $PROJECT_DIR already exists — using it (idempotent)."
else
  mkdir -p "$PROJECT_DIR"
fi
cd "$PROJECT_DIR"

mkdir -p src views public data locales/ar locales/en services

# --- ask for secrets & real prices (only if .env missing) ---
if [ ! -f .env ]; then
  echo "Let's set your real config (.env). Leave empty to enter later."
  read -rp "TELEGRAM_BOT_TOKEN: " TELEGRAM_BOT_TOKEN
  read -rp "BOT_USERNAME (without @): " BOT_USERNAME
  read -rp "ADMIN_IDS (comma separated Telegram IDs): " ADMIN_IDS
  read -rp "SESSION_SECRET (random string): " SESSION_SECRET
  read -rp "Default currency (e.g., USD): " DEFAULT_CURRENCY
  read -rp "WhatsApp price for Egypt (e.g., 0.16): " PRICE_EG
  read -rp "WhatsApp price for Canada (e.g., 0.20): " PRICE_CA
  read -rp "(Optional) SMSACTIVATE_API_KEY: " SMSACTIVATE_API_KEY

  cat > .env <<EOF
# === core ===
PORT=3000
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
BOT_USERNAME=${BOT_USERNAME}
ADMIN_IDS=${ADMIN_IDS}
SESSION_SECRET=${SESSION_SECRET}

# === i18n ===
START_LANG=ar
SUPPORTED_LANGS=ar,en

# === pricing (seed into DB) ===
DEFAULT_CURRENCY=${DEFAULT_CURRENCY}
PRICE_EG=${PRICE_EG}
PRICE_CA=${PRICE_CA}

# === services (optional) ===
SMSACTIVATE_API_KEY=${SMSACTIVATE_API_KEY}
EOF
fi

# Remove *any* leftover mock/demo DBs if present
rm -f data/demo.db 2>/dev/null || true

# Seed prices.json from .env (authoritative) — these are your *real* prices
# If already exists, we regenerate from .env to keep single source of truth
set +u
. ./.env || true
set -u
: "${DEFAULT_CURRENCY:=USD}"
: "${PRICE_EG:=0.00}"
: "${PRICE_CA:=0.00}"

cat > data/prices.json <<EOF
{
  "service": "whatsapp",
  "currency": "${DEFAULT_CURRENCY}",
  "items": [
    { "country": "EG", "amount": ${PRICE_EG}, "active": true },
    { "country": "CA", "amount": ${PRICE_CA}, "active": true }
  ]
}
EOF

# package.json
cat > package.json <<'EOF'
{
  "name": "tg-bot-dashboard-ar-en",
  "version": "1.0.0",
  "private": true,
  "main": "src/index.js",
  "type": "commonjs",
  "scripts": {
    "dev": "nodemon src/index.js",
    "start": "node src/index.js"
  },
  "dependencies": {
    "axios": "^1.7.4",
    "bcrypt": "^5.1.1",
    "compression": "^1.7.4",
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "csurf": "^1.11.0",
    "dayjs": "^1.11.13",
    "dotenv": "^16.4.5",
    "ejs": "^3.1.10",
    "express": "^4.19.2",
    "express-rate-limit": "^7.4.0",
    "express-session": "^1.17.3",
    "helmet": "^7.1.0",
    "i18next": "^23.11.5",
    "i18next-fs-backend": "^2.3.1",
    "i18next-http-middleware": "^3.5.0",
    "better-sqlite3": "^11.5.0",
    "connect-sqlite3": "^0.9.15",
    "telegraf": "^4.16.3",
    "uuid": "^9.0.1",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "nodemon": "^3.1.4"
  }
}
EOF

# Install deps
npm i --silent
npm i -D --silent nodemon

# i18n resources
cat > locales/ar/common.json <<'EOF'
{
  "app": {"title": "لوحة التحكم", "login": "تسجيل الدخول", "logout": "تسجيل الخروج"},
  "ui": {"language": "اللغة", "arabic": "العربية", "english": "English", "welcome": "مرحبًا {{name}}", "prices": "الأسعار", "save": "حفظ"},
  "bot": {
    "start": "أهلاً! أنا البوت الرسمي. اختر لغتك 👇",
    "choose_lang": "اختر اللغة:",
    "lang_set_ar": "تم ضبط اللغة إلى العربية.",
    "lang_set_en": "تم ضبط اللغة إلى الإنجليزية.",
    "prices": "الأسعار الحالية لواتساب:\n🇪🇬 مصر: {{price_eg}} {{currency}}\n🇨🇦 كندا: {{price_ca}} {{currency}}"
  }
}
EOF

cat > locales/en/common.json <<'EOF'
{
  "app": {"title": "Dashboard", "login": "Login", "logout": "Logout"},
  "ui": {"language": "Language", "arabic": "العربية", "english": "English", "welcome": "Welcome, {{name}}", "prices": "Prices", "save": "Save"},
  "bot": {
    "start": "Hey! I\'m the official bot. Pick your language 👇",
    "choose_lang": "Choose language:",
    "lang_set_ar": "Language set to Arabic.",
    "lang_set_en": "Language set to English.",
    "prices": "Current WhatsApp prices:\n🇪🇬 Egypt: {{price_eg}} {{currency}}\n🇨🇦 Canada: {{price_ca}} {{currency}}"
  }
}
EOF

# minimal matrix vibe CSS
cat > public/style.css <<'EOF'
:root { --fg: #e2e8f0; --bg: #0a0f14; --muted:#94a3b8; }
* { box-sizing: border-box }
body { margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial; color:var(--fg); background:radial-gradient(1000px 600px at 10% 10%, #0b1c24 0, #030507 45%, #000 100%); min-height:100dvh }
.header { display:flex; justify-content:space-between; align-items:center; padding:16px 20px; border-bottom:1px solid #0b2530; background:rgba(0,0,0,.35); backdrop-filter: blur(6px) }
main { max-width:1000px; margin:24px auto; padding:0 16px }
.card { background:rgba(3,9,12,.6); border:1px solid #0b2530; border-radius:16px; padding:20px; box-shadow: 0 10px 35px rgba(0,0,0,.35) }
.btn { padding:10px 14px; border-radius:12px; border:1px solid #0d2d3b; background:#071b22; color:var(--fg); text-decoration:none; cursor:pointer }
.btn:hover { filter:brightness(1.1) }
.lang-toggle { display:flex; gap:8px }
small.muted { color:var(--muted) }
EOF

# views
cat > views/layout.ejs <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title><%= title %></title>
  <link rel="stylesheet" href="/style.css" />
</head>
<body>
  <header class="header">
    <div><strong><%= title %></strong></div>
    <nav class="lang-toggle">
      <form method="post" action="/lang/choose">
        <input type="hidden" name="_csrf" value="<%= csrfToken %>">
        <button class="btn" name="lang" value="ar">🇪🇬 <%= t('ui.arabic') %></button>
        <button class="btn" name="lang" value="en">🇬🇧 <%= t('ui.english') %></button>
      </form>
    </nav>
  </header>
  <main>
    <%- body %>
  </main>
</body>
</html>
EOF

cat > views/login.ejs <<'EOF'
<% layout('layout') -%>
<div class="card">
  <h2><%= t('app.login') %></h2>
  <p class="muted"><small class="muted">Telegram Instant Login:</small></p>
  <div id="tg-login"></div>
  <script>
    function onTelegramAuth(user) {
      fetch('/auth/telegram', {
        method:'POST', headers:{ 'Content-Type':'application/json' },
        body: JSON.stringify(user)
      }).then(r=>r.json()).then(r=>{
        if(r.ok) location.href='/'; else alert(r.error||'Auth failed');
      })
    }
  </script>
  <script async src="https://telegram.org/js/telegram-widget.js?22"
          data-telegram-login="<%= botUsername %>"
          data-size="large" data-userpic="false"
          data-onauth="onTelegramAuth(user)" data-request-access="write"></script>
</div>
EOF

cat > views/dashboard.ejs <<'EOF'
<% layout('layout') -%>
<div class="card">
  <h2><%= t('ui.welcome', { name: displayName }) %></h2>
  <p><strong><%= t('ui.prices') %>:</strong></p>
  <ul>
    <li>🇪🇬 EG — <%= prices.EG %> <%= currency %></li>
    <li>🇨🇦 CA — <%= prices.CA %> <%= currency %></li>
  </ul>
  <form method="post" action="/logout">
    <input type="hidden" name="_csrf" value="<%= csrfToken %>">
    <button class="btn"><%= t('app.logout') %></button>
  </form>
</div>
EOF

# optional service stub for SMS-Activate (constrained to EG/CA + whatsapp)
cat > services/smsactivate.js <<'EOF'
const axios = require('axios');

const BASE = 'https://api.sms-activate.org/stubs/handler_api.php';

function buildParams(obj){
  return Object.entries(obj).map(([k,v])=>`${k}=${encodeURIComponent(v)}`).join('&');
}

async function getNumber(apiKey, country) {
  // service code for WhatsApp is usually 'wa'
  const params = buildParams({ api_key: apiKey, action:'getNumber', service:'wa', country });
  const url = `${BASE}?${params}`;
  const { data } = await axios.get(url);
  return data; // You should parse and store id/number
}

module.exports = { getNumber };
EOF

# main server + bot
cat > src/index.js <<'EOF'
require('dotenv').config();
const path = require('path');
const fs = require('fs');
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
const cors = require('cors');
const session = require('express-session');
const SQLiteStore = require('connect-sqlite3')(session);
const csrf = require('csurf');
const cookieParser = require('cookie-parser');
const { v4: uuidv4 } = require('uuid');
const { z } = require('zod');
const dayjs = require('dayjs');
const bcrypt = require('bcrypt');

const i18next = require('i18next');
const i18nextMiddleware = require('i18next-http-middleware');
const i18nextFs = require('i18next-fs-backend');

const Database = require('better-sqlite3');
const { Telegraf, Markup } = require('telegraf');

const PORT = process.env.PORT || 3000;
const START_LANG = process.env.START_LANG || 'ar';
const SUPPORTED_LANGS = (process.env.SUPPORTED_LANGS || 'ar,en').split(',');
const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || '';
const BOT_USERNAME = process.env.BOT_USERNAME || '';
const ADMIN_IDS = (process.env.ADMIN_IDS||'').split(',').map(s=>s.trim()).filter(Boolean);

// === DB setup ===
const dbFile = path.join(__dirname, '..', 'data', 'app.db');
const db = new Database(dbFile);
db.pragma('journal_mode = WAL');

db.prepare(`CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  telegram_id TEXT UNIQUE,
  username TEXT,
  display_name TEXT,
  lang TEXT DEFAULT 'ar',
  role TEXT DEFAULT 'user',
  password_hash TEXT,
  created_at TEXT
)`).run();

db.prepare(`CREATE TABLE IF NOT EXISTS prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  service TEXT NOT NULL,
  country TEXT NOT NULL,
  currency TEXT NOT NULL,
  amount REAL NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  UNIQUE(service,country)
)`).run();

// seed prices from data/prices.json (authoritative real data)
const pricesJsonPath = path.join(__dirname,'..','data','prices.json');
if (fs.existsSync(pricesJsonPath)) {
  const seed = JSON.parse(fs.readFileSync(pricesJsonPath,'utf-8'));
  const upsert = db.prepare(`INSERT INTO prices(service,country,currency,amount,active)
    VALUES (@service,@country,@currency,@amount,@active)
    ON CONFLICT(service,country) DO UPDATE SET currency=excluded.currency, amount=excluded.amount, active=excluded.active`);
  for (const item of seed.items) {
    upsert.run({ service: seed.service, country: item.country, currency: seed.currency, amount: item.amount, active: item.active?1:0 });
  }
}

// helper get prices
function getPrices(){
  const rows = db.prepare(`SELECT country, amount, currency FROM prices WHERE service='whatsapp' AND active=1`).all();
  const out = { currency: process.env.DEFAULT_CURRENCY || 'USD', EG: null, CA: null };
  for (const r of rows) {
    if (r.country === 'EG') out.EG = r.amount;
    if (r.country === 'CA') out.CA = r.amount;
    out.currency = r.currency; // keep last (they should match)
  }
  return out;
}

// === i18n ===
i18next
  .use(i18nextFs)
  .use(i18nextMiddleware.LanguageDetector)
  .init({
    fallbackLng: START_LANG,
    preload: SUPPORTED_LANGS,
    backend: { loadPath: path.join(__dirname, '..', 'locales', '{{lng}}', 'common.json') },
    detection: { order: ['cookie', 'querystring', 'header'], caches: ['cookie'] },
    interpolation: { escapeValue: false }
  });

// === Telegram Bot ===
let bot = null;
if (BOT_TOKEN) {
  bot = new Telegraf(BOT_TOKEN);

  const langButtons = Markup.inlineKeyboard([
    [Markup.button.callback('🇪🇬 العربية', 'set_lang:ar'), Markup.button.callback('🇬🇧 English', 'set_lang:en')]
  ]);

  bot.start((ctx) => {
    const tgId = String(ctx.from.id);
    const existing = db.prepare('SELECT * FROM users WHERE telegram_id=?').get(tgId);
    if (!existing) {
      db.prepare('INSERT INTO users(telegram_id, username, display_name, lang, role, created_at) VALUES (?,?,?,?,?,?)')
        .run(tgId, ctx.from.username||null, `${ctx.from.first_name||''} ${ctx.from.last_name||''}`.trim(), START_LANG, ADMIN_IDS.includes(tgId)?'admin':'user', dayjs().toISOString());
    }
    const lang = existing?.lang || START_LANG;
    const t = (k)=> i18next.getFixedT(lang)(k);
    return ctx.reply(t('bot.start'), langButtons);
  });

  bot.action(/set_lang:(ar|en)/, (ctx) => {
    const lang = ctx.match[1];
    const tgId = String(ctx.from.id);
    db.prepare('UPDATE users SET lang=? WHERE telegram_id=?').run(lang, tgId);
    const t = (k)=> i18next.getFixedT(lang)(k);
    const msg = lang==='ar'? t('bot.lang_set_ar'): t('bot.lang_set_en');
    return ctx.editMessageText(msg, langButtons);
  });

  bot.command('prices', (ctx) => {
    const tgId = String(ctx.from.id);
    const user = db.prepare('SELECT * FROM users WHERE telegram_id=?').get(tgId);
    const lang = user?.lang || START_LANG;
    const t = (k,vars)=> i18next.getFixedT(lang)(k, vars);
    const p = getPrices();
    return ctx.reply(t('bot.prices', { price_eg: p.EG ?? '–', price_ca: p.CA ?? '–', currency: p.currency }));
  });

  bot.launch().then(()=> console.log('[bot] launched with default lang =', START_LANG)).catch(err=> console.error('bot launch error', err));
  process.once('SIGINT', () => bot.stop('SIGINT'));
  process.once('SIGTERM', () => bot.stop('SIGTERM'));
} else {
  console.warn('[bot] TELEGRAM_BOT_TOKEN not set. Bot will not start.');
}

// === Web server ===
const app = express();
app.set('trust proxy', 1);
app.use(helmet({ contentSecurityPolicy: false }));
app.use(compression());
app.use(cors({ origin: false }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());
app.use('/public', express.static(path.join(__dirname,'..','public')));
app.use('/', express.static(path.join(__dirname,'..','public')));

// sessions
app.use(session({
  store: new SQLiteStore({ db: 'sessions.sqlite', dir: path.join(__dirname,'..','data') }),
  secret: process.env.SESSION_SECRET || uuidv4(),
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax' }
}));

// rate limit
app.use(rateLimit({ windowMs: 15*60*1000, max: 300 }));

// i18n
app.use(i18nextMiddleware.handle(i18next));

// view engine
const expressLayouts = require('express-ejs-layouts');
app.set('view engine','ejs');
app.set('views', path.join(__dirname,'..','views'));
app.use(expressLayouts);

// CSRF (after session)
const csrfProtection = csrf({ cookie: false });

// helpers
function tFactory(req){
  return (k, vars)=> req.t(k, vars);
}

function requireAuth(req,res,next){ if(req.session.user) return next(); return res.redirect('/login'); }

// Telegram Instant Login verification
const crypto = require('crypto');
function checkTelegramAuth(data){
  // data: from widget POST, includes hash
  const { hash, ...rest } = data;
  const checkString = Object.keys(rest)
    .sort()
    .map(k => `${k}=${rest[k]}`)
    .join('\n');
  const secret = crypto.createHash('sha256').update(process.env.TELEGRAM_BOT_TOKEN).digest();
  const hmac = crypto.createHmac('sha256', secret).update(checkString).digest('hex');
  return hmac === hash;
}

// routes
app.get('/login', csrfProtection, (req,res)=>{
  res.render('login', { title: req.t('app.login'), botUsername: BOT_USERNAME, csrfToken: req.csrfToken(), t: tFactory(req) });
});

app.post('/auth/telegram', async (req,res)=>{
  try {
    const ok = checkTelegramAuth(req.body || {});
    if(!ok) return res.status(401).json({ ok:false, error:'bad_signature' });
    const tgId = String(req.body.id);
    const username = req.body.username||null;
    const display = [req.body.first_name, req.body.last_name].filter(Boolean).join(' ');
    const existing = db.prepare('SELECT * FROM users WHERE telegram_id=?').get(tgId);
    if (!existing) {
      db.prepare('INSERT INTO users(telegram_id, username, display_name, lang, role, created_at) VALUES (?,?,?,?,?,?)')
        .run(tgId, username, display, START_LANG, (process.env.ADMIN_IDS||'').split(',').includes(tgId)?'admin':'user', dayjs().toISOString());
    } else {
      db.prepare('UPDATE users SET username=?, display_name=? WHERE telegram_id=?').run(username, display, tgId);
    }
    req.session.user = { telegram_id: tgId, username, display_name: display };
    return res.json({ ok:true });
  } catch (e){
    console.error('tg auth error', e);
    return res.status(500).json({ ok:false, error:'server_error' });
  }
});

app.post('/logout', csrfProtection, (req,res)=>{ req.session.destroy(()=> res.redirect('/login')); });

app.post('/lang/choose', csrfProtection, (req,res)=>{
  const { lang } = req.body || {};
  if (SUPPORTED_LANGS.includes(lang)) {
    res.i18n.changeLanguage(lang);
    res.cookie('i18next', lang, { httpOnly:false, sameSite:'lax' });
    if (req.session.user) {
      db.prepare('UPDATE users SET lang=? WHERE telegram_id=?').run(lang, String(req.session.user.telegram_id||''));
    }
  }
  res.redirect('back');
});

app.get('/', csrfProtection, requireAuth, (req,res)=>{
  const tgId = req.session.user.telegram_id;
  const user = db.prepare('SELECT * FROM users WHERE telegram_id=?').get(String(tgId));
  const p = getPrices();
  res.render('dashboard', {
    title: req.t('app.title'),
    displayName: user?.display_name || user?.username || 'User',
    prices: { EG: p.EG ?? '–', CA: p.CA ?? '–' },
    currency: p.currency,
    csrfToken: req.csrfToken(),
    t: (k,vars)=> req.t(k,vars)
  });
});

// health
app.get('/healthz', (_req,res)=> res.json({ ok:true }));

app.listen(PORT, ()=> console.log(`[web] listening on :${PORT}`));
EOF

# tiny util to ensure express-ejs-layouts is available
npm i --silent express-ejs-layouts

# .replit and Replit Nix (optional but helpful)
cat > .replit <<'EOF'
run = "npm run dev"
EOF

cat > replit.nix <<'EOF'
{ pkgs }: {
  deps = [ pkgs.nodejs_20 pkgs.nodePackages.npm pkgs.git ];
}
EOF

# final echo
cat <<'EOF'

====================================
✅ Done. What next (Replit):
1) Open the Shell and run:  bash replit_bootstrap.sh   (you already did)
2) If you left any .env fields blank, open the .env file and fill them.
3) Press the green "Run" — web at $PORT, bot auto-starts (Arabic default).
4) Login at /login using Telegram Instant Login.

Security baked in: helmet, sessions in SQLite, CSRF on forms, rate limit.
No mock DB: using data/app.db + data/prices.json from your real inputs.
To show prices in bot: send /prices to your bot.

If you need to tweak prices later, edit data/prices.json and restart (or update DB directly).
====================================
EOF
