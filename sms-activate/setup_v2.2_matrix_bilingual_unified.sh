#!/usr/bin/env bash
set -e

echo "🚀 Setting up HackerAI Matrix v2.2 (Bilingual Unified Edition)"

# stop old container
sudo docker stop sms-v2 || true
sudo docker rm sms-v2 || true

# rebuild structure
mkdir -p backend frontend data

# --- Dockerfile ---
cat > Dockerfile <<'DOCKER'
FROM node:22-bullseye
WORKDIR /app
RUN apt-get update && apt-get install -y python3 make g++ sqlite3 && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
RUN npm install --production --no-audit --no-fund
COPY . .
EXPOSE 3000
CMD ["node", "backend/server.js"]
DOCKER

# --- docker-compose.yml ---
cat > docker-compose.yml <<'COMPOSE'
version: '3.9'
services:
  sms-v2:
    build: .
    container_name: sms-v2
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./data:/app/data
    environment:
      - NODE_ENV=production
COMPOSE

# --- backend/server.js ---
cat > backend/server.js <<'SERVER'
import express from "express";
import sqlite3 from "sqlite3";
import { open } from "sqlite";
import bodyParser from "body-parser";
import path from "path";
import cors from "cors";
import rateLimit from "express-rate-limit";
import { fileURLToPath } from "url";

const app = express();
const __dirname = path.dirname(fileURLToPath(import.meta.url));

app.use(cors());
app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, "../frontend")));
app.use(rateLimit({ windowMs: 60 * 1000, max: 30 }));

const dbPromise = open({
  filename: path.join(__dirname, "../data/users.db"),
  driver: sqlite3.Database,
});

async function initDB() {
  const db = await dbPromise;
  await db.exec(`CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE,
    password TEXT,
    credit INTEGER DEFAULT 0,
    is_admin INTEGER DEFAULT 0,
    chat_id TEXT
  )`);
  await db.run(
    `INSERT OR IGNORE INTO users (username,password,is_admin)
     VALUES ('nowyouseeme','icansee',1)`
  );
  console.log("✅ DB ready & admin ensured");
}
initDB();

app.post("/api/auth/login", async (req, res) => {
  const { username, password } = req.body;
  const db = await dbPromise;
  const user = await db.get(
    "SELECT * FROM users WHERE username=? AND password=?",
    [username, password]
  );
  if (!user) return res.status(401).json({ ok: false, error: "Invalid credentials" });
  res.json({ ok: true, user });
});

app.get("/api/health", (req, res) => res.json({ ok: true, ts: new Date() }));

app.listen(3000, () => console.log("🌍 HackerAI Matrix v2.2 running on :3000"));
SERVER

# --- frontend/index.html ---
cat > frontend/index.html <<'HTML'
<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8"/>
<title>HackerAI Matrix Dashboard</title>
<style>
  body {
    font-family: 'Courier New', monospace;
    background: black;
    color: #00ff88;
    text-align: center;
    margin-top: 5vh;
  }
  .login-box {
    border: 1px solid #00ff88;
    padding: 20px;
    display: inline-block;
    border-radius: 10px;
    background: rgba(0,255,136,0.1);
  }
  input,button {
    margin: 5px;
    padding: 10px;
    background: black;
    border: 1px solid #00ff88;
    color: #00ff88;
    border-radius: 5px;
  }
</style>
</head>
<body>
<h1>🧠 HackerAI Matrix Login</h1>
<div class="login-box">
  <input id="u" placeholder="اسم المستخدم">
  <br>
  <input id="p" type="password" placeholder="كلمة المرور">
  <br>
  <button onclick="login()">تسجيل الدخول</button>
</div>
<p id="msg"></p>
<script>
function login(){
  fetch('/api/auth/login',{
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({username:document.getElementById('u').value,password:document.getElementById('p').value})
  }).then(r=>r.json()).then(d=>{
    if(d.ok) document.getElementById('msg').innerText='✅ تم تسجيل الدخول بنجاح'
    else document.getElementById('msg').innerText='❌ خطأ في تسجيل الدخول'
  }).catch(()=>document.getElementById('msg').innerText='⚠️ خطأ في الاتصال');
}
</script>
</body>
</html>
HTML

# --- package.json ---
cat > package.json <<'PKG'
{
  "name": "hackerai-matrix",
  "version": "2.2.0",
  "main": "backend/server.js",
  "type": "module",
  "scripts": {
    "start": "node backend/server.js"
  },
  "dependencies": {
    "express": "^4.19.2",
    "sqlite": "^5.1.1",
    "sqlite3": "^5.1.7",
    "body-parser": "^1.20.2",
    "cors": "^2.8.5",
    "express-rate-limit": "^7.4.0"
  }
}
PKG

echo "🧱 Building new Docker stack..."
sudo docker-compose down -v || true
sudo docker-compose up -d --build

echo "✅ Setup complete! Visit http://YOUR_IP:3000"
