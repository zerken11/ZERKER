#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# setup_v2_matrix_pro.sh
# - Deploys a Node/Express backend using SQLite (better-sqlite3)
# - Static Matrix-style dashboard frontend (login/signup/admin UI)
# - Docker + docker-compose stack
# - Creates admin user: username=nowyouseeme password=icansee (change after first login)
# - Port: 3000
# ------------------------------------------------------------------

PROJECT_DIR="$(pwd)/sms-activate-v2"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"
DATA_DIR="$PROJECT_DIR/data"

ADMIN_USER="nowyouseeme"
ADMIN_PASS="icansee"
ADMIN_EMAIL="nowyouseeme@example.local"

echo "=== V2 Matrix PRO installer ==="
echo "Project dir: $PROJECT_DIR"
echo

# Create directories
mkdir -p "$BACKEND_DIR" "$FRONTEND_DIR" "$DATA_DIR"

# ------------- Dockerfile -------------
cat > "$PROJECT_DIR/Dockerfile" <<'DOCKER'
FROM node:22-bullseye

# Install build deps for better-sqlite3
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-dev build-essential libsqlite3-dev ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --production --no-audit --no-fund

# Copy application
COPY . .

EXPOSE 3000
CMD ["node", "backend/index.js"]
DOCKER

# ------------- docker-compose.yml -------------
cat > "$PROJECT_DIR/docker-compose.yml" <<'COMPOSE'
version: '3.8'
services:
  sms-v2:
    build: .
    image: sms-activate-v2:latest
    container_name: sms-activate-v2
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./data:/app/data
    environment:
      - NODE_ENV=production
      - PORT=3000
      - SESSION_SECRET=dev-secret-change-me
COMPOSE

# ------------- package.json -------------
cat > "$PROJECT_DIR/package.json" <<'PKG'
{
  "name": "sms-activate-v2",
  "version": "1.0.0",
  "main": "backend/index.js",
  "type": "module",
  "scripts": {
    "start": "node backend/index.js"
  },
  "dependencies": {
    "better-sqlite3": "^8.2.0",
    "bcrypt": "^5.1.0",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "jsonwebtoken": "^9.0.0",
    "morgan": "^1.10.0"
  }
}
PKG

# ------------- Backend: index.js -------------
cat > "$BACKEND_DIR/index.js" <<'JS'
import express from "express";
import path from "path";
import { fileURLToPath } from "url";
import Database from "better-sqlite3";
import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import morgan from "morgan";
import fs from "fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DATA_DIR = path.join(__dirname, "../data");
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

const DB_PATH = path.join(DATA_DIR, "app.db");
const db = new Database(DB_PATH);

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.SESSION_SECRET || "dev-secret-change-me";

const app = express();
app.use(express.json());
app.use(morgan("tiny"));
app.use(express.static(path.join(__dirname, "../frontend")));

//
// DB init
//
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE,
  email TEXT,
  password_hash TEXT,
  role TEXT DEFAULT 'user',
  credits INTEGER DEFAULT 0,
  banned INTEGER DEFAULT 0,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER,
  action TEXT,
  meta TEXT,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
`);

function logAction(user_id, action, meta="") {
  const stmt = db.prepare("INSERT INTO logs (user_id, action, meta) VALUES (?, ?, ?)");
  stmt.run(user_id || null, action, meta);
}

// create admin on first run if none exists
const adminExists = db.prepare("SELECT COUNT(1) as c FROM users WHERE role='admin'").get();
if (!adminExists.c) {
  const defaultUser = process.env.ADMIN_USERNAME || "nowyouseeme";
  const defaultPass = process.env.ADMIN_PASSWORD || "icansee";
  const salt = bcrypt.genSaltSync(10);
  const hash = bcrypt.hashSync(defaultPass, salt);
  const stmt = db.prepare("INSERT INTO users (username, email, password_hash, role, credits) VALUES (?, ?, ?, 'admin', 1000)");
  stmt.run(defaultUser, process.env.ADMIN_EMAIL || "nowyouseeme@example.local", hash);
  console.log("Created default admin user:", defaultUser);
}

//
// Helpers
//
function generateToken(user) {
  return jwt.sign({ id: user.id, username: user.username, role: user.role }, JWT_SECRET, { expiresIn: "7d" });
}
function authMiddleware(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.replace(/^Bearer\s+/i, "");
  if (!token) return res.status(401).json({ ok:false, error:"no token" });
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch(e) { return res.status(401).json({ ok:false, error:"invalid token" }); }
}
function adminOnly(req, res, next) {
  if (!req.user) return res.status(401).json({ ok:false });
  if (req.user.role !== 'admin') return res.status(403).json({ ok:false, error:"admin only" });
  next();
}

//
// Public endpoints
//
app.get("/api/health", (req,res)=>res.json({ ok:true, ts:new Date().toISOString() }));

app.post("/api/auth/signup", (req,res)=>{
  const { username, email, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok:false, error:"missing" });
  try {
    const salt = bcrypt.genSaltSync(10);
    const hash = bcrypt.hashSync(password, salt);
    const stmt = db.prepare("INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)");
    const info = stmt.run(username, email || "", hash);
    logAction(info.lastInsertRowid, "signup", username);
    res.json({ ok:true });
  } catch(e) {
    res.status(400).json({ ok:false, error: String(e) });
  }
});

app.post("/api/auth/login", (req,res)=>{
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ ok:false, error:"missing" });
  const user = db.prepare("SELECT * FROM users WHERE username = ?").get(username);
  if (!user) return res.status(401).json({ ok:false, error:"invalid" });
  if (user.banned) return res.status(403).json({ ok:false, error:"banned" });
  const ok = bcrypt.compareSync(password, user.password_hash);
  if (!ok) return res.status(401).json({ ok:false, error:"invalid" });
  const token = generateToken(user);
  logAction(user.id, "login");
  res.json({ ok:true, token, user: { id: user.id, username: user.username, role: user.role, credits: user.credits } });
});

app.get("/api/me", authMiddleware, (req,res)=>{
  const user = db.prepare("SELECT id,username,role,credits,banned FROM users WHERE id = ?").get(req.user.id);
  res.json({ ok:true, user });
});

//
// User endpoints
//
app.get("/api/me/logs", authMiddleware, (req,res)=>{
  const logs = db.prepare("SELECT * FROM logs WHERE user_id = ? ORDER BY ts DESC LIMIT 100").all(req.user.id);
  res.json({ ok:true, logs });
});

//
// Admin endpoints
//
app.get("/api/admin/users", authMiddleware, adminOnly, (req,res)=>{
  const users = db.prepare("SELECT id,username,email,role,credits,banned,created_at FROM users ORDER BY id DESC").all();
  res.json({ ok:true, users });
});

app.post("/api/admin/add-credit", authMiddleware, adminOnly, (req,res)=>{
  const { userId, delta } = req.body || {};
  if (typeof userId === "undefined" || typeof delta === "undefined") return res.status(400).json({ ok:false });
  const stmt = db.prepare("UPDATE users SET credits = credits + ? WHERE id = ?");
  stmt.run(delta, userId);
  logAction(req.user.id, "admin_add_credit", JSON.stringify({ userId, delta }));
  res.json({ ok:true });
});

app.post("/api/admin/ban-user", authMiddleware, adminOnly, (req,res)=>{
  const { userId } = req.body || {};
  db.prepare("UPDATE users SET banned = 1 WHERE id = ?").run(userId);
  logAction(req.user.id, "admin_ban", JSON.stringify({ userId }));
  res.json({ ok:true });
});
app.post("/api/admin/unban-user", authMiddleware, adminOnly, (req,res)=>{
  const { userId } = req.body || {};
  db.prepare("UPDATE users SET banned = 0 WHERE id = ?").run(userId);
  logAction(req.user.id, "admin_unban", JSON.stringify({ userId }));
  res.json({ ok:true });
});

app.get("/api/admin/logs", authMiddleware, adminOnly, (req,res)=>{
  const logs = db.prepare("SELECT logs.*, users.username FROM logs LEFT JOIN users ON users.id = logs.user_id ORDER BY logs.ts DESC LIMIT 500").all();
  res.json({ ok:true, logs });
});

//
// Serve frontend (SPA)
//
app.get("/*", (req,res) => {
  // Let API routes 404 naturally; otherwise serve index.html for SPA.
  if (req.path.startsWith("/api/")) return res.status(404).json({ ok:false });
  res.sendFile(path.join(__dirname, "../frontend/index.html"));
});

app.listen(PORT, ()=>console.log("✅ Matrix PRO server listening on", PORT));
JS

# ------------- Frontend: index.html (Matrix-style UI) -------------
cat > "$FRONTEND_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>MSDash — Matrix PRO</title>
<style>
  :root{
    --bg:#000;
    --accent:#00ff41;
    --muted:#0b3b0b;
    --panel:#041204;
    --text:#a8ffa8;
  }
  *{box-sizing:border-box}
  html,body{height:100%;margin:0;font-family:Inter,ui-sans-serif,system-ui,Segoe UI,Roboto,"Helvetica Neue",Arial;}
  body{background:linear-gradient(0deg,#001200 0%, #000 100%); color:var(--text); overflow:hidden;}
  /* matrix rain background */
  canvas#rain{position:fixed;left:0;top:0;width:100%;height:100%;z-index:0;mix-blend-mode:screen;opacity:0.9;}
  .app{position:relative;z-index:2;display:flex;height:100vh;gap:24px;padding:32px;}
  .card{background:rgba(0,0,0,0.55);border:1px solid rgba(0,255,65,0.08);padding:20px;border-radius:8px;backdrop-filter: blur(4px);box-shadow: 0 6px 30px rgba(0,0,0,0.6);}
  .left{flex:1;min-width:320px}
  .right{width:420px}
  h1{font-weight:700;margin:0 0 10px;color:var(--accent)}
  small{color:#8fdc8f}
  input,button,select{padding:10px;border-radius:6px;border:1px solid rgba(0,255,65,0.06);background:rgba(0,0,0,0.6);color:var(--text);width:100%;margin-top:8px}
  button.primary{background:var(--accent);color:#000;border:none;font-weight:700;cursor:pointer}
  .muted{color:#6fbf6f}
  nav{display:flex;gap:8px;margin-bottom:12px}
  table{width:100%;border-collapse:collapse;color:var(--text)}
  th,td{padding:8px;border-bottom:1px dashed rgba(0,255,65,0.04);font-size:13px;text-align:left}
  .small{font-size:12px;color:#86d686}
  .admin-actions button{margin-right:8px}
  .hidden{display:none}
  .top-right{position:fixed;right:18px;top:14px;z-index:10}
</style>
</head>
<body>
<canvas id="rain"></canvas>

<div class="top-right">
  <button id="toggleTheme">Toggle Light</button>
</div>

<div class="app">
  <div class="left card">
    <h1>📱 MSDash — Matrix PRO</h1>
    <div id="notlogged">
      <p class="muted">Welcome — please login or sign up</p>
      <div style="display:flex;gap:12px">
        <div style="flex:1">
          <h4>Login</h4>
          <input id="login_user" placeholder="username" />
          <input id="login_pass" placeholder="password" type="password" />
          <button id="btnLogin" class="primary">Login</button>
        </div>
        <div style="flex:1">
          <h4>Signup</h4>
          <input id="su_user" placeholder="username" />
          <input id="su_pass" placeholder="password" type="password" />
          <button id="btnSignup">Create</button>
        </div>
      </div>
    </div>

    <div id="dashboard" class="hidden">
      <p class="small">Logged in as <strong id="who"></strong> — credits: <span id="credits"></span></p>
      <div style="display:flex;gap:12px;margin-top:12px">
        <button id="btnRefresh">Refresh</button>
        <button id="btnLogout">Logout</button>
      </div>

      <h3 style="margin-top:16px">Recent logs</h3>
      <div id="logs" style="max-height:300px;overflow:auto;background:rgba(0,0,0,0.4);padding:8px;border-radius:6px"></div>
    </div>
  </div>

  <div class="right card" id="adminPanel" style="display:none;">
    <h3>Admin Panel</h3>
    <div id="adminUI">
      <p class="small">Users</p>
      <div style="max-height:420px;overflow:auto">
        <table id="usersTable"><thead><tr><th>id</th><th>user</th><th>credits</th><th>role</th><th>ban</th><th>actions</th></tr></thead><tbody></tbody></table>
      </div>
      <h4 style="margin-top:10px">Logs</h4>
      <div id="adminLogs" style="max-height:200px;overflow:auto;background:#020202;padding:8px;border-radius:6px"></div>
    </div>
  </div>
</div>

<script>
/* Matrix rain (lightweight) */
(() => {
  const c = document.getElementById('rain');
  const ctx = c.getContext('2d');
  function resize(){c.width=innerWidth;c.height=innerHeight}
  addEventListener('resize', resize); resize();
  const cols = Math.floor(c.width/14);
  const y = Array(cols).fill(0);
  function step(){
    ctx.fillStyle='rgba(0,0,0,0.06)';
    ctx.fillRect(0,0,c.width,c.height);
    ctx.fillStyle='#00ff41';
    ctx.font = '12px monospace';
    for(let i=0;i<y.length;i++){
      const char = String.fromCharCode(0x30A0 + Math.random()*96);
      ctx.fillText(char, i*14, y[i]*14);
      if(y[i]*14 > c.height && Math.random()>0.975) y[i]=0;
      y[i] += 1;
    }
    requestAnimationFrame(step);
  }
  step();
})();

/* App logic */
const api = (path, opts={}) => fetch('/api'+path, opts).then(r=>r.json ? r.json() : r.text()).catch(e=>({ok:false,error:e+''}));
let token = localStorage.getItem('msdash_token') || null;
function setToken(t){ token=t; if(t) localStorage.setItem('msdash_token', t); else localStorage.removeItem('msdash_token'); }
function authFetch(path, opts={}) {
  opts.headers = opts.headers || {};
  opts.headers['Content-Type'] = 'application/json';
  if(token) opts.headers['Authorization'] = 'Bearer '+token;
  return fetch('/api'+path, opts).then(r => {
    if(r.status === 401) { setToken(null); renderUI(); throw 'unauth'; }
    return r.json();
  });
}

async function renderUI(){
  if(!token) {
    document.getElementById('notlogged').classList.remove('hidden');
    document.getElementById('dashboard').classList.add('hidden');
    document.getElementById('adminPanel').style.display='none';
    return;
  }
  try {
    const me = await authFetch('/me');
    if(!me.ok) { setToken(null); return renderUI(); }
    const u = me.user;
    document.getElementById('who').innerText = u.username;
    document.getElementById('credits').innerText = u.credits;
    document.getElementById('notlogged').classList.add('hidden');
    document.getElementById('dashboard').classList.remove('hidden');
    // logs
    const logs = await authFetch('/me/logs');
    if(logs.ok) {
      const L = logs.logs || [];
      document.getElementById('logs').innerHTML = L.map(l=>`<div class="small">[${l.ts}] ${l.action} ${l.meta?('- '+l.meta):''}</div>`).join('');
    }
    // admin?
    if(u.role==='admin'){
      document.getElementById('adminPanel').style.display='block';
      loadAdmin();
    } else {
      document.getElementById('adminPanel').style.display='none';
    }
  } catch(e){ console.error(e); setToken(null); renderUI(); }
}

document.getElementById('btnLogin').addEventListener('click', async ()=>{
  const user=document.getElementById('login_user').value.trim();
  const pass=document.getElementById('login_pass').value;
  const res = await api('/auth/login', { method:'POST', body: JSON.stringify({ username:user, password:pass }), headers:{'Content-Type':'application/json'} });
  if(res.ok){ setToken(res.token); alert('Welcome '+res.user.username); renderUI(); } else alert('Login failed: '+(res.error||''));
});
document.getElementById('btnSignup').addEventListener('click', async ()=>{
  const user=document.getElementById('su_user').value.trim();
  const pass=document.getElementById('su_pass').value;
  const res = await api('/auth/signup', { method:'POST', body: JSON.stringify({ username:user, password:pass }), headers:{'Content-Type':'application/json'} });
  if(res.ok) alert('Created — please login'); else alert('Signup failed: '+(res.error||''));
});
document.getElementById('btnLogout').addEventListener('click', ()=>{ setToken(null); renderUI(); });
document.getElementById('btnRefresh').addEventListener('click', renderUI);

/* Admin functions */
async function loadAdmin(){
  const r = await authFetch('/admin/users');
  if(!r.ok) return;
  const tbody = document.querySelector('#usersTable tbody');
  tbody.innerHTML = r.users.map(u=>{
    return `<tr>
      <td>${u.id}</td>
      <td>${u.username}</td>
      <td>${u.credits}</td>
      <td>${u.role}</td>
      <td>${u.banned? 'yes':'no'}</td>
      <td class="admin-actions">
        <button onclick="modCredit(${u.id}, 100)">+100</button>
        <button onclick="modCredit(${u.id}, -100)">-100</button>
        <button onclick="ban(${u.id})">${u.banned? 'Unban':'Ban'}</button>
      </td>
    </tr>`;
  }).join('');
  const logs = await authFetch('/admin/logs');
  document.getElementById('adminLogs').innerHTML = (logs.logs||[]).slice(0,200).map(l=>`<div class="small">[${l.ts}] ${l.username||'system'} - ${l.action} ${l.meta||''}</div>`).join('');
}
window.modCredit = async (id, delta)=> {
  await authFetch('/admin/add-credit', { method:'POST', body:JSON.stringify({ userId:id, delta }), headers:{'Content-Type':'application/json'}});
  await loadAdmin(); renderUI();
}
window.ban = async (id)=>{
  // toggle
  const users = (await authFetch('/admin/users')).users;
  const u = users.find(x=>x.id===id);
  if(u.banned) await authFetch('/admin/unban-user',{ method:'POST', body: JSON.stringify({ userId:id }), headers:{'Content-Type':'application/json'} });
  else await authFetch('/admin/ban-user',{ method:'POST', body: JSON.stringify({ userId:id }), headers:{'Content-Type':'application/json'} });
  await loadAdmin(); renderUI();
}

/* Toggle theme (matrix green on black vs light) */
document.getElementById('toggleTheme').addEventListener('click', () => {
  if(document.body.style.background.includes('linear-gradient')) {
    document.body.style.background = '#fff'; document.body.style.color = '#000';
    document.querySelectorAll('.card').forEach(c=>c.style.background='rgba(255,255,255,0.85)');
    document.getElementById('toggleTheme').innerText='Toggle Dark';
  } else {
    location.reload();
  }
});

/* auto refresh */
setInterval(()=>{ if(localStorage.getItem('msdash_token')) renderUI(); }, 10000);

/* initial render */
renderUI();
</script>
</body>
</html>
HTML

# ------------- final notes & start -------------
echo "Files written. Building container..."

cd "$PROJECT_DIR"
# stop existing container if present
docker-compose down -v || true
docker-compose up -d --build

echo
echo "=== Finished ==="
echo "Dashboard should be available at http://YOUR_SERVER_IP:3000 (or your domain proxied to port 3000)"
echo "Admin user: $ADMIN_USER  /  password: (the one you requested)"
echo "You must change the admin password after first login!"
