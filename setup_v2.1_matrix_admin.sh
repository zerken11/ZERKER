#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up SMS-Activate v2.1 (Matrix Admin, Node 22 + SQLite)"

# ---- CONFIG (edit if you like) ----
APP_NAME="sms-v2"
PORT="3000"
ADMIN_USER="${ADMIN_USER:-nowyouseeme}"
ADMIN_PASS="${ADMIN_PASS:-icansee}"
JWT_SECRET="${JWT_SECRET:-change-me-please-$(openssl rand -hex 16 2>/dev/null || echo abc123)}"
SECURE_COOKIES="${SECURE_COOKIES:-true}"   # set false if you only use http://127.0.0.1:3000

# ---- Prep dirs ----
mkdir -p backend frontend backend/data

# ---- Dockerfile (Node 22 + build deps for better-sqlite3) ----
cat > Dockerfile <<'DOCKER'
FROM node:22-bullseye

# build tools + sqlite cli for debugging (optional)
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ sqlite3 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./
RUN npm install --production --no-audit --no-fund
COPY . .
EXPOSE 3000
CMD ["node","backend/server.js"]
DOCKER

# ---- docker-compose ----
cat > docker-compose.yml <<COMPOSE
version: "3.9"
services:
  $APP_NAME:
    build: .
    container_name: $APP_NAME
    restart: unless-stopped
    ports:
      - "${PORT}:3000"
    environment:
      NODE_ENV: "production"
      PORT: "3000"
      JWT_SECRET: "${JWT_SECRET}"
      ADMIN_USER: "${ADMIN_USER}"
      ADMIN_PASS: "${ADMIN_PASS}"
      SECURE_COOKIES: "${SECURE_COOKIES}"
    volumes:
      - ./backend/data:/app/backend/data
COMPOSE

# ---- package.json (CommonJS for simplicity) ----
cat > package.json <<'PKG'
{
  "name": "sms-activate-matrix",
  "version": "2.1.0",
  "private": true,
  "main": "backend/server.js",
  "scripts": {
    "start": "node backend/server.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "better-sqlite3": "^12.4.1",
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "express-rate-limit": "^6.7.0",
    "jsonwebtoken": "^9.0.2",
    "morgan": "^1.10.0"
  }
}
PKG

# ---- backend/server.js ----
cat > backend/server.js <<'SERVER'
const path = require('path');
const fs = require('fs');
const express = require('express');
const cookieParser = require('cookie-parser');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const Database = require('better-sqlite3');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const morgan = require('morgan');

const app = express();
app.set('trust proxy', 1);

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';
const SECURE_COOKIES = String(process.env.SECURE_COOKIES || 'true').toLowerCase() === 'true';

const DATA_DIR = path.join(__dirname, 'data');
const DB_PATH = path.join(DATA_DIR, 'app.db');
fs.mkdirSync(DATA_DIR, { recursive: true });
const db = new Database(DB_PATH);

// --- schema ---
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',
  credits INTEGER NOT NULL DEFAULT 0,
  banned INTEGER NOT NULL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER,
  action TEXT NOT NULL,
  meta TEXT,
  ts TEXT DEFAULT (datetime('now'))
);
`);

function logAction(userId, action, metaObj = null) {
  db.prepare(`INSERT INTO logs(user_id, action, meta) VALUES (?, ?, ?);`)
    .run(userId || null, action, metaObj ? JSON.stringify(metaObj) : null);
}

// ensure admin
(function ensureAdmin() {
  const adminUser = process.env.ADMIN_USER || 'admin';
  const adminPass = process.env.ADMIN_PASS || 'change-me';
  const found = db.prepare(`SELECT id FROM users WHERE username=?`).get(adminUser);
  const hash = bcrypt.hashSync(adminPass, 10);
  if (!found) {
    db.prepare(`INSERT INTO users(username,password,role,credits,banned) VALUES (?,?,?,?,0)`)
      .run(adminUser, hash, 'admin', 0);
    console.log(`✅ Admin created: ${adminUser}`);
    logAction(null, 'admin_created', { username: adminUser });
  } else {
    // keep admin role, update password to ensure access
    db.prepare(`UPDATE users SET password=?, role='admin' WHERE username=?`).run(hash, adminUser);
    console.log(`✅ Admin ensured: ${adminUser} (password refreshed)`);
    logAction(found.id, 'admin_ensured', { username: adminUser });
  }
})();

// --- middleware ---
app.use(morgan('tiny'));
app.use(express.json());
app.use(cookieParser());

// CORS (works for same-origin; if you later host dashboard elsewhere, it still works)
app.use(cors({
  origin: true,
  credentials: true
}));

// basic rate limit
app.use('/api/', rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false
}));

// static dashboard
app.use(express.static(path.join(__dirname, '../frontend'), {
  index: 'index.html',
  maxAge: '5m'
}));

// --- auth helpers ---
function setSessionCookie(res, payload) {
  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' });
  res.cookie('sid', token, {
    httpOnly: true,
    sameSite: 'lax',
    secure: SECURE_COOKIES,
    maxAge: 7 * 24 * 3600 * 1000
  });
}

function authRequired(req, res, next) {
  try {
    const token = req.cookies.sid;
    if (!token) return res.status(401).json({ ok: false, error: 'NO_AUTH' });
    const data = jwt.verify(token, JWT_SECRET);
    req.user = data;
    // check banned
    const row = db.prepare(`SELECT banned FROM users WHERE id=?`).get(data.id);
    if (row && row.banned) return res.status(403).json({ ok:false, error:'BANNED' });
    next();
  } catch (e) {
    return res.status(401).json({ ok: false, error: 'BAD_TOKEN' });
  }
}

function adminRequired(req, res, next) {
  if (!req.user || req.user.role !== 'admin') {
    return res.status(403).json({ ok:false, error: 'ADMIN_ONLY' });
  }
  next();
}

// --- routes ---
app.get('/api/health', (req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

app.post('/api/auth/signup', (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok:false, error:'MISSING' });
  try {
    const hash = bcrypt.hashSync(password, 10);
    const info = db.prepare(`INSERT INTO users(username,password,role,credits,banned) VALUES (?,?,?,?,0)`)
      .run(username.trim(), hash, 'user', 0);
    logAction(info.lastInsertRowid, 'signup', { username });
    const user = { id: info.lastInsertRowid, username, role:'user' };
    setSessionCookie(res, user);
    return res.json({ ok:true, user });
  } catch (e) {
    if (String(e).includes('UNIQUE')) return res.status(409).json({ ok:false, error:'TAKEN' });
    return res.status(500).json({ ok:false, error:'ERR' });
  }
});

app.post('/api/auth/login', (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok:false, error:'MISSING' });
  const row = db.prepare(`SELECT id,username,password,role,banned FROM users WHERE username=?`).get(username);
  if (!row) return res.status(401).json({ ok:false, error:'BAD_CREDENTIALS' });
  if (row.banned) return res.status(403).json({ ok:false, error:'BANNED' });
  if (!bcrypt.compareSync(password, row.password)) return res.status(401).json({ ok:false, error:'BAD_CREDENTIALS' });
  const user = { id: row.id, username: row.username, role: row.role };
  setSessionCookie(res, user);
  logAction(row.id, 'login', {});
  return res.json({ ok:true, user });
});

app.post('/api/auth/logout', (req, res) => {
  res.clearCookie('sid', { httpOnly:true, sameSite:'lax', secure: SECURE_COOKIES });
  res.json({ ok:true });
});

app.get('/api/auth/me', authRequired, (req, res) => {
  const u = db.prepare(`SELECT id,username,role,credits,banned,created_at FROM users WHERE id=?`).get(req.user.id);
  res.json({ ok:true, user: u });
});

// --- admin ---
app.get('/api/admin/users', authRequired, adminRequired, (req, res) => {
  const list = db.prepare(`SELECT id,username,role,credits,banned,created_at FROM users ORDER BY id DESC`).all();
  res.json({ ok:true, users:list });
});

app.post('/api/admin/users/credit', authRequired, adminRequired, (req, res) => {
  const { userId, delta } = req.body || {};
  if (!userId || !Number.isFinite(delta)) return res.status(400).json({ ok:false, error:'MISSING' });
  const u = db.prepare(`SELECT id,credits FROM users WHERE id=?`).get(userId);
  if (!u) return res.status(404).json({ ok:false, error:'NOT_FOUND' });
  db.prepare(`UPDATE users SET credits=credits+? WHERE id=?`).run(delta, userId);
  logAction(req.user.id, 'credit_change', { target:userId, delta });
  const updated = db.prepare(`SELECT id,username,role,credits,banned,created_at FROM users WHERE id=?`).get(userId);
  res.json({ ok:true, user: updated });
});

app.post('/api/admin/users/ban', authRequired, adminRequired, (req, res) => {
  const { userId, banned } = req.body || {};
  if (!userId || typeof banned !== 'boolean') return res.status(400).json({ ok:false, error:'MISSING' });
  const u = db.prepare(`SELECT id FROM users WHERE id=?`).get(userId);
  if (!u) return res.status(404).json({ ok:false, error:'NOT_FOUND' });
  db.prepare(`UPDATE users SET banned=? WHERE id=?`).run(banned ? 1 : 0, userId);
  logAction(req.user.id, banned ? 'ban' : 'unban', { target:userId });
  const updated = db.prepare(`SELECT id,username,role,credits,banned,created_at FROM users WHERE id=?`).get(userId);
  res.json({ ok:true, user: updated });
});

app.get('/api/admin/logs', authRequired, adminRequired, (req, res) => {
  const limit = Math.min(500, Math.max(1, Number(req.query.limit || 100)));
  const rows = db.prepare(`SELECT id,user_id,action,meta,ts FROM logs ORDER BY id DESC LIMIT ?`).all(limit);
  res.json({ ok:true, logs: rows });
});

// fallback to dashboard
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../frontend/index.html'));
});

app.listen(PORT, () => {
  console.log(`✅ Matrix Dashboard API live on :${PORT}`);
});
SERVER

# ---- frontend/index.html (Matrix neon UI + admin tools) ----
cat > frontend/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>🧠 Matrix Dashboard</title>
<style>
  :root{--bg:#060a08;--fg:#a8ffb3;--muted:#4db66b;--card:#0a120e;--accent:#00ff88;--danger:#ff4d4d;}
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 ui-sans-serif,system-ui,Segoe UI,Roboto}
  .grid{display:grid;place-items:center;height:100vh;padding:24px}
  .panel{width:min(1100px,95vw);background:linear-gradient(180deg,#07110c,#030704);border:1px solid #0f2e20;border-radius:18px;box-shadow:0 10px 30px #000a;overflow:hidden}
  .head{display:flex;justify-content:space-between;align-items:center;padding:18px 22px;border-bottom:1px solid #0f2e20;background:#08120d}
  .logo{display:flex;gap:12px;align-items:center} .logo b{font-size:18px;letter-spacing:.6px}
  .btn{background:#062; border:1px solid #0a4; color:#b9ffd0; padding:10px 14px; border-radius:10px; cursor:pointer}
  .btn:hover{filter:brightness(1.2)} .btn.red{background:#3a0505;border-color:#6a0a0a;color:#ffb0b0}
  .body{padding:22px;display:grid;gap:18px}
  .row{display:flex;gap:16px;flex-wrap:wrap}
  .card{background:var(--card);border:1px solid #123b29;border-radius:14px;padding:16px;flex:1;min-width:260px}
  input,select{width:100%;padding:10px 12px;background:#02150d;border:1px solid #0b3f2a;color:var(--fg);border-radius:10px}
  table{width:100%;border-collapse:collapse;font-size:14px}
  th,td{border-bottom:1px solid #0e2f22;padding:8px 10px;text-align:left}
  .muted{color:var(--muted)} .ok{color:var(--accent)} .bad{color:var(--danger)}
  .mono{font-family:ui-monospace,Menlo,Consolas,monospace}
  .login{max-width:360px;margin:40px auto;display:grid;gap:12px}
  .hidden{display:none}
</style>
</head>
<body>
  <div class="grid">
    <div class="panel">
      <div class="head">
        <div class="logo"><span class="mono ok">matrix://</span><b>SMS Activate</b></div>
        <div>
          <button class="btn" id="btnLogout" onclick="logout()" title="Logout">⏻ Logout</button>
        </div>
      </div>
      <div class="body" id="app">
        <!-- LOGIN -->
        <div id="viewLogin">
          <div class="card">
            <h3>🧠 Matrix Login</h3>
            <div class="login">
              <input id="u" placeholder="username" autocomplete="username"/>
              <input id="p" placeholder="password" type="password" autocomplete="current-password"/>
              <div class="row">
                <button class="btn" onclick="login()">Login</button>
                <button class="btn" onclick="signup()">Signup</button>
              </div>
              <div class="muted mono" id="loginMsg"></div>
            </div>
          </div>
          <div class="row">
            <div class="card"><b>Health</b><div class="mono" id="health">checking…</div></div>
          </div>
        </div>

        <!-- DASH -->
        <div id="viewDash" class="hidden">
          <div class="row">
            <div class="card"><b>User</b><div class="mono" id="me"></div></div>
            <div class="card"><b>Health</b><div class="mono" id="health2"></div></div>
          </div>

          <div id="adminZone" class="hidden">
            <div class="card">
              <b>👥 Users</b>
              <table id="tblUsers"><thead><tr>
                <th>ID</th><th>User</th><th>Role</th><th>Credits</th><th>Banned</th><th>Actions</th>
              </tr></thead><tbody></tbody></table>
            </div>

            <div class="card">
              <b>📜 Logs</b>
              <table id="tblLogs"><thead><tr>
                <th>#</th><th>User</th><th>Action</th><th>Meta</th><th>Time</th>
              </tr></thead><tbody></tbody></table>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>

<script>
const $ = (s)=>document.querySelector(s);
const API = (path, opts={}) => fetch(path, { credentials:'include', ...opts });

async function ping(){
  try{
    const r = await API('/api/health'); const j = await r.json();
    $('#health').textContent = 'OK @ '+j.ts; $('#health2').textContent = 'OK @ '+j.ts;
  }catch{ $('#health').textContent='offline'; $('#health2').textContent='offline'; }
}
setInterval(ping, 10000); ping();

function showLogin(){ $('#viewLogin').classList.remove('hidden'); $('#viewDash').classList.add('hidden'); }
function showDash(){ $('#viewDash').classList.remove('hidden'); $('#viewLogin').classList.add('hidden'); }

async function me(){
  const r = await API('/api/auth/me');
  if(!r.ok){ showLogin(); return; }
  const { user } = await r.json();
  $('#me').textContent = JSON.stringify(user);
  showDash();
  if(user.role === 'admin'){ $('#adminZone').classList.remove('hidden'); loadUsers(); loadLogs(); }
  else { $('#adminZone').classList.add('hidden'); }
}
me();

async function login(){
  const body = JSON.stringify({ username: $('#u').value.trim(), password: $('#p').value });
  const r = await API('/api/auth/login', { method:'POST', headers:{'Content-Type':'application/json'}, body });
  const j = await r.json();
  if(!r.ok){ $('#loginMsg').textContent = '❌ '+(j.error||'bad'); return; }
  $('#loginMsg').textContent = '✅ Welcome '+j.user.username;
  me();
}

async function signup(){
  const body = JSON.stringify({ username: $('#u').value.trim(), password: $('#p').value });
  const r = await API('/api/auth/signup', { method:'POST', headers:{'Content-Type':'application/json'}, body });
  const j = await r.json();
  if(!r.ok){ $('#loginMsg').textContent = '❌ '+(j.error||'bad'); return; }
  $('#loginMsg').textContent = '✅ Signed in as '+j.user.username;
  me();
}

async function logout(){
  await API('/api/auth/logout', { method:'POST' });
  showLogin();
}

async function loadUsers(){
  const r = await API('/api/admin/users'); if(!r.ok) return;
  const { users } = await r.json();
  const tbody = $('#tblUsers tbody'); tbody.innerHTML='';
  users.forEach(u=>{
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${u.id}</td>
      <td>${u.username}</td>
      <td>${u.role}</td>
      <td><span class="mono">${u.credits}</span></td>
      <td>${u.banned ? '<span class="bad">yes</span>' : '<span class="ok">no</span>'}</td>
      <td>
        <button class="btn" onclick="credit(${u.id}, 1)">+1</button>
        <button class="btn" onclick="credit(${u.id}, -1)">-1</button>
        <button class="btn ${u.banned?'':'red'}" onclick="ban(${u.id}, ${u.banned? 'false':'true'})">${u.banned?'Unban':'Ban'}</button>
      </td>`;
    tbody.appendChild(tr);
  });
}

async function credit(id, delta){
  const r = await API('/api/admin/users/credit', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ userId:id, delta }) });
  if(r.ok) loadUsers();
}

async function ban(id, flag){
  const r = await API('/api/admin/users/ban', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ userId:id, banned:!!flag }) });
  if(r.ok) loadUsers();
}

async function loadLogs(){
  const r = await API('/api/admin/logs?limit=200'); if(!r.ok) return;
  const { logs } = await r.json();
  const tbody = $('#tblLogs tbody'); tbody.innerHTML='';
  logs.forEach(l=>{
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${l.id}</td>
      <td>${l.user_id ?? '-'}</td>
      <td>${l.action}</td>
      <td class="mono">${l.meta || ''}</td>
      <td class="mono">${l.ts}</td>`;
    tbody.appendChild(tr);
  });
}
</script>
</body>
</html>
HTML

# ---- stop old, build, up ----
echo "🧹 Stopping old containers (ignore errors if not present)…"
docker rm -f "$APP_NAME" >/dev/null 2>&1 || true
docker rm -f sms-activate >/dev/null 2>&1 || true
docker rm -f myapp >/dev/null 2>&1 || true

echo "🔨 Building image…"
docker compose build

echo "🚢 Starting stack…"
docker compose up -d

echo "✅ Done. Health check:"
curl -s http://127.0.0.1:${PORT}/api/health || true
echo
echo "➡️  If your Nginx already proxies 443 -> http://127.0.0.1:${PORT}, open your domain to use the dashboard."
echo "   Admin: ${ADMIN_USER} / ${ADMIN_PASS}"
echo "   Secure cookies: ${SECURE_COOKIES} (set SECURE_COOKIES=false to test on http://127.0.0.1:${PORT})"
