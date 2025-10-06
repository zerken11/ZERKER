#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up HackerAI Matrix v2.2 (Unified Bot + Dashboard, Bilingual)"

# Config — you can override with environment variables before running
BOT_TOKEN="${BOT_TOKEN:-8416511820:AAGKA_gfFXGLvKXKSlP_qcYWDcUUPY-TqTg}"
ADMIN_IDS="${ADMIN_IDS:-8190845140,725797724}"
BOT_USERNAME="${BOT_USERNAME:-@Fake_Wa_bot}"
DEFAULT_LANG="${DEFAULT_LANG:-ar}"    # 'ar' or 'en'

APP_NAME="hackerai-matrix"
PORT="3000"

# Step 1: Clean old containers
docker rm -f $APP_NAME 2>/dev/null || true
docker rm -f sms-activate sms-v2 2>/dev/null || true

# Step 2: Write Dockerfile
cat > Dockerfile << 'DOCKER'
FROM node:22-bullseye
WORKDIR /app

# Install build tools + sqlite3 for native modules
RUN apt-get update && apt-get install -y python3 make g++ sqlite3 && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm install --production --no-audit --no-fund
COPY . .
EXPOSE 3000
CMD ["node", "backend/server.js"]
DOCKER

# Step 3: docker-compose.yml
cat > docker-compose.yml << 'COMPOSE'
version: '3.9'
services:
  $APP_NAME:
    build: .
    container_name: $APP_NAME
    restart: unless-stopped
    ports:
      - "${PORT}:3000"
    environment:
      BOT_TOKEN: "$BOT_TOKEN"
      ADMIN_IDS: "$ADMIN_IDS"
      BOT_USERNAME: "$BOT_USERNAME"
      DEFAULT_LANG: "$DEFAULT_LANG"
COMPOSE

# Step 4: package.json
cat > package.json << 'PKG'
{
  "name": "hackerai-matrix",
  "version": "2.2.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node backend/server.js"
  },
  "dependencies": {
    "axios": "^1.3.6",
    "bcryptjs": "^2.4.3",
    "body-parser": "^1.20.2",
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.3.0",
    "jsonwebtoken": "^9.0.2",
    "morgan": "^1.10.0",
    "sqlite3": "^5.1.6",
    "telegraf": "^4.12.3"
  }
}
PKG

# Step 5: backend/server.js + bot + dashboard logic
mkdir -p backend frontend backend/data
cat > backend/server.js << 'SERVER'
import express from "express";
import { Telegraf } from "telegraf";
import sqlite3 from "sqlite3";
import path from "path";
import { fileURLToPath } from "url";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import cors from "cors";
import rateLimit from "express-rate-limit";
import morgan from "morgan";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.join(__dirname, "data/users.db");
const botToken = process.env.BOT_TOKEN;
const adminIds = (process.env.ADMIN_IDS || "").split(",");
const defaultLang = process.env.DEFAULT_LANG || "ar";

const db = new sqlite3.Database(DB_PATH);
const app = express();
app.use(express.json());
app.use(cors({ origin: true, credentials: true }));
app.use(morgan("tiny"));
app.use(rateLimit({ windowMs: 60000, max: 100 }));

// Create tables if not exist
db.serialize(() => {
  db.run("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, telegram_id TEXT UNIQUE, username TEXT, password TEXT, credits INTEGER DEFAULT 0, role TEXT DEFAULT 'user', banned INTEGER DEFAULT 0, lang TEXT DEFAULT ?) ", defaultLang);
  db.run("CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, action TEXT, meta TEXT, ts TEXT DEFAULT (datetime('now')))");

  // Seed admin users by telegram_id
  adminIds.forEach(id => {
    if (!id) return;
    db.get("SELECT * FROM users WHERE telegram_id=?", [id], (err, row) => {
      if (!row) {
        db.run("INSERT INTO users(telegram_id, username, role, credits, lang) VALUES (?, ?, 'admin', 0, ?)", [id, `admin_${id}`, defaultLang]);
        console.log('✅ Admin seeded via telegram_id:', id);
      }
    });
  });
});

// JWT helpers
function signToken(user) {
  return jwt.sign(user, process.env.JWT_SECRET || "default_secret", { expiresIn: '7d' });
}

function authMiddleware(req, res, next) {
  try {
    const token = req.cookies?.sid || req.headers["authorization"]?.split(" ")[1];
    if (!token) return res.status(401).json({ ok: false, error: "no_token" });
    const user = jwt.verify(token, process.env.JWT_SECRET || "default_secret");
    req.user = user;
    // check banned
    db.get("SELECT banned FROM users WHERE id=?", [user.id], (e, row) => {
      if (row && row.banned) return res.status(403).json({ ok: false, error: "banned" });
      next();
    });
  } catch (e) {
    return res.status(401).json({ ok: false, error: "bad_token" });
  }
}

// --- Routes ---

app.get("/api/health", (_, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

app.post("/api/auth/login", (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ ok: false, error: "missing" });
  }
  db.get("SELECT * FROM users WHERE username=?", [username.trim()], (err, row) => {
    if (!row) return res.status(401).json({ ok: false, error: "invalid" });
    if (!bcrypt.compareSync(password, row.password)) {
      return res.status(401).json({ ok: false, error: "invalid" });
    }
    const user = { id: row.id, username: row.username, role: row.role, telegram_id: row.telegram_id };
    const token = signToken(user);
    res.json({ ok: true, user, token });
  });
});

app.get("/api/auth/me", authMiddleware, (req, res) => {
  db.get("SELECT id, username, role, credits, telegram_id, lang FROM users WHERE id=?", [req.user.id], (err, row) => {
    res.json({ ok: true, user: row });
  });
});

app.post("/api/auth/logout", (_, res) => {
  res.json({ ok: true });
});

// Telegram webhook route (for handling login via bot)
const bot = new Telegraf(botToken);
bot.start(async ctx => {
  const chatId = String(ctx.chat.id);
  const username = ctx.from.username || `tg_${chatId}`;
  // Upsert user
  db.run("INSERT OR IGNORE INTO users(telegram_id, username, lang) VALUES (?, ?, ?)", [chatId, username, defaultLang]);
  ctx.reply(defaultLang === "ar" ? "مرحبًا بكم في لوحة HackerAI Matrix 👽" : "Welcome to HackerAI Matrix 👽");
  ctx.reply(defaultLang === "ar" ? "اضغط للدخول إلى اللوحة" : "Tap to enter dashboard", {
    reply_markup: {
      inline_keyboard: [
        [{
          text: defaultLang === "ar" ? "📂 افتح اللوحة" : "📂 Open Dashboard",
          url: `https://${ctx.update.message?.chat?.username ? ctx.update.message.chat.username : ""}${ctx.update.message.chat.id}`
        }]
      ]
    }
  });
});

// Launch bot inside same process
bot.launch();

// Static frontend + fallback
app.use(express.static(path.join(__dirname, "../frontend")));
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "../frontend/index.html"));
});

// Launch HTTP server
import cookieParser from "cookie-parser";
app.use(cookieParser());
app.listen(PORT, () => {
  console.log("✅ HackerAI Matrix v2.2 unified live on portal", PORT);
});
SERVER

# Step 6: frontend/index.html (bilingual + matrix UI)
cat > frontend/index.html << 'HTML'
<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8"/>
<title>لوحة HackerAI Matrix</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<style>
  body { margin:0; padding:0; background: black; color: #0f0; font-family: monospace; overflow: hidden; }
  #rain { position: fixed; top:0; left:0; width:100%; height:100%; z-index:-1; }
  .container { position: relative; z-index:10; display:flex; flex-direction:column; align-items:center; justify-content:center; height:100vh; }
  input,button { background:#011; color:#0f0; border:1px solid #0f0; padding:10px; margin:5px; border-radius:5px; }
  .toggle { position:absolute; top:20px; right:20px; cursor:pointer; color:#0f0; }
  .hidden { display: none; }
</style>
<canvas id="rain"></canvas>
</head>
<body>
<div class="toggle" onclick="toggleLang()">🌍</div>
<div class="container" id="loginBox">
  <h1>🧠 تسجيل الدخول / Telegram</h1>
  <input id="u" placeholder="اسم المستخدم (اختياري)" autocomplete="username"/>
  <input id="p" type="password" placeholder="كلمة المرور (اختياري)" autocomplete="current-password"/>
  <button onclick="login()">تسجيل الدخول</button>
  <button onclick="signup()">إنشاء حساب</button>
  <p id="msg"></p>
  <button onclick="loginTelegram()">🔗 تسجيل الدخول عبر Telegram</button>
  <div class="mono" id="health">…</div>
</div>

<script>
const API = (p, o={}) => fetch(p, { credentials:'include', ...o });
const langState = { code: 'ar' };

function toggleLang(){
  langState.code = langState.code === 'ar' ? 'en' : 'ar';
  location.reload();
}

async function ping(){
  try {
    const r = await API('/api/health');
    const j = await r.json();
    document.getElementById('health').textContent = (langState.code==='ar'? 'الحالة':'Status') + ': ✅ ' + j.ts;
  } catch {
    document.getElementById('health').textContent = (langState.code==='ar'?'غير متصل':'offline');
  }
}
setInterval(ping,3000);
ping();

function loginTelegram(){
  // open bot link
  window.open(`https://t.me/${encodeURIComponent("${BOT_USERNAME.replace('@','')}")}`, '_blank');
}

async function login(){
  const u = document.getElementById('u').value.trim(), p = document.getElementById('p').value;
  const r = await API('/api/auth/login', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ username:u, password:p }) });
  const j = await r.json();
  document.getElementById('msg').textContent = j.ok ? (langState.code==='ar'?'أهلاً':'Welcome') + ' '+(j.user.username||j.user.telegram_id) : '❌ '+j.error;
  if (j.ok) {
    window.location.reload();
  }
}

// Matrix rain effect
const canvas = document.getElementById('rain');
const ctx = canvas.getContext('2d');
canvas.width = window.innerWidth;
canvas.height = window.innerHeight;
const cols = Math.floor(canvas.width/20)+1;
const drops = Array(cols).fill(1);
function draw(){
  ctx.fillStyle = 'rgba(0,0,0,0.1)'; ctx.fillRect(0,0,canvas.width,canvas.height);
  ctx.fillStyle = '#0f0'; ctx.font = '20px monospace';
  drops.forEach((y,i) => {
    const text = String.fromCharCode(0x0627 + Math.random()*58);
    ctx.fillText(text, i*20, y*20);
    if (y*20 > canvas.height || Math.random()>0.975) drops[i]=0;
    drops[i]++;
  });
}
setInterval(draw, 50);
</script>
</body>
</html>
HTML

# Step 7: Launch
echo "🚧 Building & deploying..."
docker compose down -v || true
docker compose build
docker compose up -d
echo "✅ Deployed!"

echo "Visit your dashboard at https://fakew.cyou (Telegram login integrated, Arabic-first UI)."
