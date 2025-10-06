#!/usr/bin/env bash
set -e
echo "🚀 Setting up SMS-Activate Matrix v2.1 Admin Stack"

sudo docker stop sms-v2 2>/dev/null || true
sudo docker rm sms-v2 2>/dev/null || true
sudo docker system prune -af

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
    environment:
      - NODE_ENV=production
      - PORT=3000
COMPOSE

# --- backend/server.js ---
mkdir -p backend frontend backend/data
cat > backend/server.js <<'SERVER'
import express from "express";
import sqlite3 from "sqlite3";
import path from "path";
import { fileURLToPath } from "url";
import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import cors from "cors";
import rateLimit from "express-rate-limit";
import fs from "fs";

const app = express();
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const db = new sqlite3.Database(path.join(__dirname, "data/users.db"));

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, "../frontend")));
app.use(rateLimit({ windowMs: 60 * 1000, max: 100 }));

// --- DB Setup ---
db.run("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT, password TEXT, credits INTEGER DEFAULT 0, role TEXT DEFAULT 'user')");

// --- Admin Auto Creation ---
const adminUser = "nowyouseeme";
const adminPass = "icansee";
db.get("SELECT * FROM users WHERE username=?", [adminUser], (err, row) => {
  if (!row) {
    const hash = bcrypt.hashSync(adminPass, 10);
    db.run("INSERT INTO users(username,password,credits,role) VALUES(?,?,?,?)", [adminUser, hash, 9999, "admin"]);
    console.log("👑 Admin user created: nowyouseeme / icansee");
  }
});

// --- Routes ---
app.post("/api/auth/login", (req, res) => {
  const { username, password } = req.body;
  db.get("SELECT * FROM users WHERE username=?", [username], (err, row) => {
    if (!row) return res.status(401).json({ error: "Invalid credentials" });
    if (!bcrypt.compareSync(password, row.password)) return res.status(401).json({ error: "Invalid credentials" });
    const token = jwt.sign({ id: row.id, username: row.username, role: row.role }, "secret", { expiresIn: "2h" });
    res.json({ ok: true, token });
  });
});

app.get("/api/auth/me", (req, res) => {
  const auth = req.headers.authorization;
  if (!auth) return res.status(401).json({ error: "Missing token" });
  try {
    const data = jwt.verify(auth.split(" ")[1], "secret");
    res.json({ ok: true, user: data });
  } catch {
    res.status(401).json({ error: "Invalid token" });
  }
});

app.get("/api/health", (_, res) => res.json({ ok: true, ts: new Date() }));

app.listen(3000, () => console.log("✅ Matrix Dashboard API live on :3000"));
SERVER

# --- frontend/index.html ---
cat > frontend/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>🧠 Matrix Admin Login</title>
<style>
body { background:#000; color:#0f0; font-family: monospace; text-align:center; padding-top:10vh; }
input,button { background:#111; color:#0f0; border:1px solid #0f0; padding:8px; margin:5px; }
</style>
</head>
<body>
<h1>🧠 Matrix Login</h1>
<input id="u" placeholder="username"><br>
<input id="p" type="password" placeholder="password"><br>
<button onclick="login()">Login</button>
<p id="msg"></p>
<script>
async function login(){
  let r=await fetch('/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:u.value,password:p.value})});
  let d=await r.json();msg.innerText=d.ok?'✅ Welcome '+u.value:'❌ '+(d.error||'Login failed');
}
</script>
</body>
</html>
HTML

# --- package.json ---
cat > package.json <<'PKG'
{
  "name": "sms-matrix-admin",
  "version": "2.1.0",
  "type": "module",
  "dependencies": {
    "bcrypt": "^5.1.1",
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.3.0",
    "jsonwebtoken": "^9.0.2",
    "sqlite3": "^5.1.6"
  }
}
PKG

echo "🚧 Building and launching Docker container..."
sudo docker-compose down -v || true
sudo docker-compose up -d --build

echo "✅ Done! Visit http://YOUR_DOMAIN:3000 (admin: nowyouseeme / icansee)"
