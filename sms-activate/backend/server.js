import express from "express";
import sqlite3 from "sqlite3";
import { open } from "sqlite";
import path from "path";
import bodyParser from "body-parser";
import cors from "cors";
import rateLimit from "express-rate-limit";

const app = express();
app.use(cors());
app.use(bodyParser.json());
app.use(express.static(path.join(process.cwd(), "frontend")));
app.use(rateLimit({ windowMs: 60 * 1000, max: 30 }));

const dbPath = path.join(process.cwd(), "data", "users.db");

async function initDB() {
  const db = await open({ filename: dbPath, driver: sqlite3.Database });
  await db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE,
      password TEXT,
      credit INTEGER DEFAULT 0,
      is_admin INTEGER DEFAULT 0,
      chat_id TEXT
    );
  `);

  // --- AUTO MIGRATION: ensure missing columns exist ---
  const columns = (await db.all("PRAGMA table_info(users);")).map(c => c.name);
  const required = ["credit", "is_admin", "chat_id"];
  for (const col of required) {
    if (!columns.includes(col)) {
      console.log("Adding missing column:", col);
      if (col === "credit") await db.exec("ALTER TABLE users ADD COLUMN credit INTEGER DEFAULT 0");
      if (col === "is_admin") await db.exec("ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0");
      if (col === "chat_id") await db.exec("ALTER TABLE users ADD COLUMN chat_id TEXT");
    }
  }

  await db.run(`
    INSERT OR IGNORE INTO users (username,password,is_admin)
    VALUES ('nowyouseeme','icansee',1)
  `);

  console.log("✅ DB ready & admin ensured");
  return db;
}

const dbPromise = initDB();

app.post("/api/auth/login", async (req, res) => {
  const { username, password } = req.body;
  const db = await dbPromise;
  const user = await db.get("SELECT * FROM users WHERE username=? AND password=?", [username, password]);
  if (!user) return res.status(401).json({ ok: false, error: "Invalid credentials" });
  res.json({ ok: true, user });
});

app.get("/api/health", (req, res) => res.json({ ok: true, ts: new Date() }));

app.listen(3000, () => console.log("HackerAI Matrix v2.3 running on :3000"));
