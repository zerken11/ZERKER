const Database = require("better-sqlite3");
const path = require("path");
const fs = require("fs");

const DB_FILE = path.join(__dirname, "..", "data", "app.db");
const JSON_DB_PATH = path.join(__dirname, "..", "data", "db.json");

let db = null;

function init() {
  const dir = path.dirname(DB_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  db = new Database(DB_FILE);
  db.pragma("journal_mode = WAL");

  db.prepare(
    `CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    balance REAL DEFAULT 0,
    credits_cents INTEGER DEFAULT 0,
    first_name TEXT,
    username TEXT,
    username_local TEXT,
    pass_hash TEXT,
    lang TEXT DEFAULT 'en',
    created_at TEXT
  )`,
  ).run();

  try {
    db.prepare(
      "ALTER TABLE users ADD COLUMN credits_cents INTEGER DEFAULT 0",
    ).run();
  } catch (e) {}

  db.prepare(
    `CREATE TABLE IF NOT EXISTS activations (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    phone TEXT,
    service TEXT,
    country TEXT,
    price REAL,
    code TEXT,
    status TEXT DEFAULT 'waiting',
    created_at TEXT
  )`,
  ).run();

  db.prepare(
    `CREATE TABLE IF NOT EXISTS tokens (
    token TEXT PRIMARY KEY,
    uid TEXT NOT NULL,
    created_at INTEGER,
    expires_at INTEGER
  )`,
  ).run();

  db.prepare(
    `CREATE TABLE IF NOT EXISTS prices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    service TEXT NOT NULL,
    country TEXT NOT NULL,
    currency TEXT NOT NULL,
    amount REAL NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    UNIQUE(service, country)
  )`,
  ).run();

  db.prepare(
    `CREATE TABLE IF NOT EXISTS credit_tx (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    admin_tg_id TEXT NOT NULL,
    user_tg_id TEXT NOT NULL,
    delta_cents INTEGER NOT NULL,
    note TEXT
  )`,
  ).run();

  db.prepare(
    `CREATE INDEX IF NOT EXISTS idx_users_username_local ON users(username_local)`,
  ).run();
  db.prepare(
    `CREATE INDEX IF NOT EXISTS idx_activations_user_id ON activations(user_id)`,
  ).run();
  db.prepare(`CREATE INDEX IF NOT EXISTS idx_tokens_uid ON tokens(uid)`).run();

  seedPrices();
  migrateFromJSON();
}

function seedPrices() {
  const pricesJsonPath = path.join(__dirname, "..", "data", "prices.json");
  if (!fs.existsSync(pricesJsonPath)) return;

  try {
    const seed = JSON.parse(fs.readFileSync(pricesJsonPath, "utf-8"));
    const upsert =
      db.prepare(`INSERT INTO prices(service, country, currency, amount, active)
      VALUES (@service, @country, @currency, @amount, @active)
      ON CONFLICT(service, country) DO UPDATE SET currency=excluded.currency, amount=excluded.amount, active=excluded.active`);

    for (const item of seed.items) {
      upsert.run({
        service: seed.service,
        country: item.country,
        currency: seed.currency,
        amount: item.amount,
        active: item.active ? 1 : 0,
      });
    }
  } catch (err) {
    console.warn("⚠️  Failed to seed prices from JSON:", err.message);
  }
}

function migrateFromJSON() {
  if (!fs.existsSync(JSON_DB_PATH)) return;

  try {
    const jsonData = JSON.parse(fs.readFileSync(JSON_DB_PATH, "utf8"));

    if (jsonData.users) {
      const insertUser =
        db.prepare(`INSERT OR IGNORE INTO users (id, balance, first_name, username, username_local, pass_hash, lang, created_at) 
        VALUES (@id, @balance, @first_name, @username, @username_local, @pass_hash, @lang, @created_at)`);

      for (const [id, user] of Object.entries(jsonData.users)) {
        insertUser.run({
          id: String(id),
          balance: user.balance || 0,
          first_name: user.first_name || user.firstName || null,
          username: user.username || null,
          username_local: user.username_local || null,
          pass_hash: user.passHash || null,
          lang: user.lang || "en",
          created_at: user.createdAt || new Date().toISOString(),
        });
      }
    }

    if (jsonData.activations) {
      const insertAct =
        db.prepare(`INSERT OR IGNORE INTO activations (id, user_id, phone, service, country, price, code, status, created_at)
        VALUES (@id, @user_id, @phone, @service, @country, @price, @code, @status, @created_at)`);

      for (const [id, act] of Object.entries(jsonData.activations)) {
        insertAct.run({
          id: String(id),
          user_id: String(act.userId),
          phone: act.phone || null,
          service: act.service || null,
          country: act.country || null,
          price: act.price || 0,
          code: act.code || null,
          status: act.status || "waiting",
          created_at: act.createdAt || new Date().toISOString(),
        });
      }
    }

    if (jsonData.tokens) {
      const insertToken = db.prepare(
        `INSERT OR IGNORE INTO tokens (token, uid, created_at, expires_at) VALUES (@token, @uid, @created_at, @expires_at)`,
      );

      for (const [token, data] of Object.entries(jsonData.tokens)) {
        insertToken.run({
          token,
          uid: String(data.uid),
          created_at: data.createdAt || Date.now(),
          expires_at: data.expiresAt || null,
        });
      }
    }

    console.log("✅ Migrated data from JSON to SQLite");

    const backupPath = JSON_DB_PATH + ".backup";
    fs.renameSync(JSON_DB_PATH, backupPath);
    console.log(`✅ JSON backup saved to ${backupPath}`);
  } catch (err) {
    console.warn("⚠️  JSON migration warning:", err.message);
  }
}

function upsertUser(user) {
  const id = String(user.id);
  const existing = db.prepare("SELECT * FROM users WHERE id = ?").get(id);

  if (existing) {
    const updates = [];
    const params = { id };

    if (user.balance !== undefined) {
      updates.push("balance = @balance");
      params.balance = user.balance;
    }
    if (user.first_name !== undefined) {
      updates.push("first_name = @first_name");
      params.first_name = user.first_name;
    }
    if (user.firstName !== undefined) {
      updates.push("first_name = @first_name");
      params.first_name = user.firstName;
    }
    if (user.username !== undefined) {
      updates.push("username = @username");
      params.username = user.username;
    }
    if (user.username_local !== undefined) {
      updates.push("username_local = @username_local");
      params.username_local = user.username_local;
    }
    if (user.passHash !== undefined) {
      updates.push("pass_hash = @pass_hash");
      params.pass_hash = user.passHash;
    }
    if (user.lang !== undefined) {
      updates.push("lang = @lang");
      params.lang = user.lang;
    }

    if (updates.length > 0) {
      db.prepare(`UPDATE users SET ${updates.join(", ")} WHERE id = @id`).run(
        params,
      );
    }
  } else {
    db.prepare(
      `INSERT INTO users (id, balance, first_name, username, username_local, pass_hash, lang, created_at)
      VALUES (@id, @balance, @first_name, @username, @username_local, @pass_hash, @lang, @created_at)`,
    ).run({
      id,
      balance: user.balance || 0,
      first_name: user.first_name || user.firstName || null,
      username: user.username || null,
      username_local: user.username_local || null,
      pass_hash: user.passHash || null,
      lang: user.lang || "en",
      created_at: new Date().toISOString(),
    });
  }

  return getUser(id);
}

function getUser(id) {
  const row = db.prepare("SELECT * FROM users WHERE id = ?").get(String(id));
  if (!row) return null;
  return {
    id: row.id,
    balance: row.balance,
    credits_cents: row.credits_cents || 0,
    first_name: row.first_name,
    firstName: row.first_name,
    username: row.username,
    username_local: row.username_local,
    passHash: row.pass_hash,
    lang: row.lang,
    createdAt: row.created_at,
  };
}

function getUserByUsername(username) {
  const row = db
    .prepare("SELECT * FROM users WHERE LOWER(username_local) = LOWER(?)")
    .get(String(username));
  if (!row) return null;
  return {
    id: row.id,
    balance: row.balance,
    credits_cents: row.credits_cents || 0,
    first_name: row.first_name,
    firstName: row.first_name,
    username: row.username,
    username_local: row.username_local,
    passHash: row.pass_hash,
    lang: row.lang,
    createdAt: row.created_at,
  };
}

function addCredit(id, amount) {
  const key = String(id);
  const existing = getUser(key);

  if (!existing) {
    upsertUser({ id: key, balance: amount });
    return amount;
  }

  const newBalance = (existing.balance || 0) + amount;
  db.prepare("UPDATE users SET balance = ? WHERE id = ?").run(newBalance, key);
  return newBalance;
}

function deductCredit(id, amount) {
  const key = String(id);
  const user = getUser(key);

  if (!user) throw new Error("USER_NOT_FOUND");
  const bal = user.balance || 0;
  if (bal < amount) throw new Error("INSUFFICIENT_FUNDS");

  const newBalance = bal - amount;
  db.prepare("UPDATE users SET balance = ? WHERE id = ?").run(newBalance, key);
  return newBalance;
}

function listUsers(limit = 50) {
  const rows = db
    .prepare("SELECT * FROM users ORDER BY created_at DESC LIMIT ?")
    .all(limit);
  return rows.map((row) => ({
    id: row.id,
    balance: row.balance,
    first_name: row.first_name,
    firstName: row.first_name,
    username: row.username,
    username_local: row.username_local,
    passHash: row.pass_hash,
    lang: row.lang,
    createdAt: row.created_at,
  }));
}

function setPasswordHash(id, username_local, hash) {
  const key = String(id);
  upsertUser({ id: key, username_local, passHash: hash });
  return getUser(key);
}

function setUserLang(id, lang) {
  db.prepare("UPDATE users SET lang = ? WHERE id = ?").run(lang, String(id));
}

function getUserLang(id) {
  const user = getUser(String(id));
  return user ? user.lang : "en";
}

function saveActivation(act) {
  db.prepare(
    `INSERT OR REPLACE INTO activations (id, user_id, phone, service, country, price, code, status, created_at)
    VALUES (@id, @user_id, @phone, @service, @country, @price, @code, @status, @created_at)`,
  ).run({
    id: String(act.id),
    user_id: String(act.userId),
    phone: act.phone || null,
    service: act.service || null,
    country: act.country || null,
    price: act.price || 0,
    code: act.code || null,
    status: act.status || "waiting",
    created_at: act.createdAt || new Date().toISOString(),
  });
}

function getActivation(id) {
  const row = db
    .prepare("SELECT * FROM activations WHERE id = ?")
    .get(String(id));
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    phone: row.phone,
    service: row.service,
    country: row.country,
    price: row.price,
    code: row.code,
    status: row.status,
    createdAt: row.created_at,
  };
}

function listUserActivations(uid, limit = 10) {
  const rows = db
    .prepare(
      "SELECT * FROM activations WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
    )
    .all(String(uid), limit);
  return rows.map((row) => ({
    id: row.id,
    userId: row.user_id,
    phone: row.phone,
    service: row.service,
    country: row.country,
    price: row.price,
    code: row.code,
    status: row.status,
    createdAt: row.created_at,
  }));
}

function updateActivation(id, patch) {
  const existing = getActivation(id);
  if (!existing) return null;

  const merged = { ...existing, ...patch };
  saveActivation(merged);
  return getActivation(id);
}

function createToken(token, uid, ttlMs = 1000 * 60 * 60 * 24 * 7) {
  db.prepare(
    `INSERT OR REPLACE INTO tokens (token, uid, created_at, expires_at) VALUES (?, ?, ?, ?)`,
  ).run(token, String(uid), Date.now(), Date.now() + ttlMs);
}

function resolveToken(token) {
  const row = db.prepare("SELECT * FROM tokens WHERE token = ?").get(token);
  if (!row) return null;
  if (row.expires_at && Date.now() > row.expires_at) return null;
  return row.uid;
}

function getPrices() {
  const rows = db
    .prepare(
      `SELECT country, amount, currency FROM prices WHERE service='whatsapp' AND active=1`,
    )
    .all();
  const result = { currency: "USD", EG: null, CA: null };
  for (const r of rows) {
    if (r.country === "EG") result.EG = r.amount;
    if (r.country === "CA") result.CA = r.amount;
    result.currency = r.currency;
  }
  return result;
}

function updatePrice(service, country, amount) {
  db.prepare(
    `UPDATE prices SET amount = ? WHERE service = ? AND country = ?`,
  ).run(amount, service, country);
}

function getUserByTgId(tgId) {
  return getUser(String(tgId));
}

function isAdminTg(tgId) {
  const user = getUserByTgId(tgId);
  return !!(user && user.role === "admin");
}

function formatMoney(cents) {
  return (Number(cents || 0) / 100).toFixed(2);
}

function parseAmountToCents(amountStr) {
  const s = String(amountStr || "").trim();
  if (s === "") return null;
  const n = Number(s);
  if (!isFinite(n)) return null;
  const cents = Math.round(n * 100);
  if (Math.abs(n * 100 - cents) > 0.0001) return null;
  return cents;
}

function getUserByIdentifier(x) {
  if (!x) return null;
  const s = String(x).trim();
  const numeric = s !== "" && [...s].every((ch) => ch >= "0" && ch <= "9");
  if (numeric) return getUserByTgId(s);
  return getUserByUsername(s.replace(/^@/, ""));
}

function addCreditCents(targetTgId, deltaCents, adminTgId, note) {
  const u = getUserByTgId(String(targetTgId));
  if (!u) return { ok: false, error: "user_not_found" };

  const current = u.credits_cents || 0;
  const newBal = current + deltaCents;
  if (newBal < 0) return { ok: false, error: "insufficient_balance" };

  db.prepare("UPDATE users SET credits_cents = ? WHERE id = ?").run(
    newBal,
    String(targetTgId),
  );
  db.prepare(
    "INSERT INTO credit_tx(created_at, admin_tg_id, user_tg_id, delta_cents, note) VALUES (?,?,?,?,?)",
  ).run(
    new Date().toISOString(),
    String(adminTgId),
    String(targetTgId),
    deltaCents,
    note || null,
  );

  return { ok: true, newBal };
}

function getCreditsCents(tgId) {
  const u = getUserByTgId(String(tgId));
  return u ? u.credits_cents || 0 : 0;
}

module.exports = {
  init,
  upsertUser,
  getUser,
  getUserByUsername,
  getUserByTgId,
  getUserByIdentifier,
  isAdminTg,
  addCredit,
  deductCredit,
  listUsers,
  setPasswordHash,
  setUserLang,
  getUserLang,
  saveActivation,
  getActivation,
  listUserActivations,
  updateActivation,
  createToken,
  resolveToken,
  getPrices,
  updatePrice,
  formatMoney,
  parseAmountToCents,
  addCreditCents,
  getCreditsCents,
};
