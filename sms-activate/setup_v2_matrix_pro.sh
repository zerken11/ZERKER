#!/usr/bin/env bash
set -e
echo "🚀 Setting up SMS-Activate Matrix Dashboard (v2 Pro, SQLite + Login + Credits)"

# Clean start
sudo rm -rf backend frontend docker-compose.yml Dockerfile package.json package-lock.json
mkdir -p backend frontend

# === Dockerfile ===
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

# === docker-compose.yml ===
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
COMPOSE

# === backend/server.js ===
cat > backend/server.js <<'SERVER'
import express from "express";
import path from "path";
import { fileURLToPath } from "url";
import sqlite3 from "sqlite3";
import bodyParser from "body-parser";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const db = new sqlite3.Database("./data/users.db");

// DB setup
db.run("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE, password TEXT, credits INTEGER DEFAULT 0, role TEXT DEFAULT 'user')");

app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, "../frontend")));

app.post("/api/signup", (req, res) => {
  const { username, password } = req.body;
  db.run("INSERT INTO users(username,password) VALUES(?,?)", [username, password], err => {
    if (err) return res.status(400).json({ error: "User exists" });
    res.json({ ok: true });
  });
});

app.post("/api/login", (req, res) => {
  const { username, password } = req.body;
  db.get("SELECT * FROM users WHERE username=? AND password=?", [username, password], (err, row) => {
    if (err || !row) return res.status(401).json({ error: "Invalid credentials" });
    res.json({ ok: true, user: row });
  });
});

app.get("/api/health", (_, res) => res.json({ ok: true, ts: new Date() }));

app.listen(3000, () => console.log("✅ Matrix Dashboard API live on :3000"));
SERVER

# === frontend/index.html ===
cat > frontend/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Matrix Dashboard</title>
  <style>
    body{margin:0;padding:0;background:black;color:#00ff00;font-family:monospace;text-align:center;}
    .login{margin-top:20vh;}
    input,button{padding:10px;margin:5px;border-radius:5px;border:none;font-size:1rem;}
    button{background:#00ff00;color:black;cursor:pointer;}
  </style>
</head>
<body>
  <div class="login">
    <h1>🧠 Matrix Login</h1>
    <input id="user" placeholder="Username"><br>
    <input id="pass" placeholder="Password" type="password"><br>
    <button onclick="login()">Login</button>
    <button onclick="signup()">Signup</button>
    <p id="msg"></p>
  </div>
  <script>
    async function login(){
      const res = await fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:user.value,password:pass.value})});
      const d=await res.json();msg.innerText=d.ok?'✅ Welcome '+d.user.username:'❌ '+(d.error||'Error');
    }
    async function signup(){
      const res = await fetch('/api/signup',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:user.value,password:pass.value})});
      const d=await res.json();msg.innerText=d.ok?'🎉 Account created!':'❌ '+(d.error||'Error');
    }
  </script>
</body>
</html>
HTML

# === package.json ===
cat > package.json <<'PKG'
{
  "name": "sms-matrix-v2",
  "version": "2.0.0",
  "main": "backend/server.js",
  "type": "module",
  "scripts": { "start": "node backend/server.js" },
  "dependencies": {
    "body-parser": "^1.20.2",
    "express": "^4.19.2",
    "sqlite3": "^5.1.6"
  }
}
PKG

echo "🧱 Building Docker..."
sudo docker-compose down -v || true
sudo docker-compose up -d --build

echo "✅ Done. Visit http://YOUR_IP:3000 to see your Matrix dashboard."

