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
