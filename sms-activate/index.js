// Express entry point for API + static frontend
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = process.env.PORT || 4000;
const JWT_SECRET = process.env.JWT_SECRET || process.env.SESSION_SECRET || 'dev-secret';

// --- middleware
app.use(cors());
app.use(express.json());

// --- tiny JSON "db" on top of data/db.json (non-blocking, tiny project-friendly)
const DATA_DIR = path.join(__dirname, 'data');
const DB_FILE = path.join(DATA_DIR, 'db.json');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(DB_FILE)) fs.writeFileSync(DB_FILE, JSON.stringify({ users: {}, purchases: [] }, null, 2));

function readDB() {
  try { return JSON.parse(fs.readFileSync(DB_FILE, 'utf8')); }
  catch { return { users: {}, purchases: [] }; }
}
function writeDB(db) {
  fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2));
}

// --- auth helpers
function signToken(payload) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' });
}
function authOptional(req, _res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (token) {
    try { req.user = jwt.verify(token, JWT_SECRET); } catch {}
  }
  next();
}
function requireAuth(req, res, next) {
  authOptional(req, res, () => {
    if (!req.user) return res.status(401).json({ ok: false, error: 'Unauthorized' });
    next();
  });
}
function requireAdmin(req, res, next) {
  requireAuth(req, res, () => {
    if (req.user.role !== 'admin') return res.status(403).json({ ok: false, error: 'Forbidden' });
    next();
  });
}

app.use(authOptional);

// --- API: auth
// Strategy:
// - If ADMIN_EMAIL/ADMIN_PASSWORD provided, those creds become admin; everyone else is "user" (any password accepted unless you want to hard-enforce).
// - Token is returned; client stores in localStorage and sends as Bearer token.
app.post('/api/auth/login', (req, res) => {
  const { email, password } = req.body || {};
  if (!email) return res.status(400).json({ ok: false, error: 'Email required' });

  const adminEmail = process.env.ADMIN_EMAIL || 'admin@local';
  const adminPass  = process.env.ADMIN_PASSWORD || 'admin';

  let role = 'user';
  if (email === adminEmail) {
    if (password !== adminPass) return res.status(401).json({ ok: false, error: 'Invalid admin credentials' });
    role = 'admin';
  }

  // upsert user record
  const db = readDB();
  db.users[email] = db.users[email] || { email, credits: 0, role };
  // keep admin role sticky
  if (email === adminEmail) db.users[email].role = 'admin';
  writeDB(db);

  const token = signToken({ email, role: db.users[email].role });
  res.json({ ok: true, token });
});

app.get('/api/me', requireAuth, (req, res) => {
  const db = readDB();
  const u = db.users[req.user.email] || { email: req.user.email, credits: 0, role: 'user' };
  res.json({ ok: true, email: u.email, credits: u.credits, role: u.role });
});

app.post('/api/logout', (_req, res) => {
  // client just drops its token; nothing server-side to do with stateless JWTs
  res.json({ ok: true });
});

// --- API: admin
app.get('/api/admin/users', requireAdmin, (_req, res) => {
  const db = readDB();
  res.json({ ok: true, users: Object.values(db.users) });
});

app.post('/api/admin/add-credit', requireAdmin, (req, res) => {
  const { email, amount } = req.body || {};
  const n = Number(amount);
  if (!email || Number.isNaN(n)) return res.status(400).json({ ok: false, error: 'email and numeric amount required' });

  const db = readDB();
  db.users[email] = db.users[email] || { email, credits: 0, role: 'user' };
  db.users[email].credits = Number(db.users[email].credits || 0) + n;
  writeDB(db);
  res.json({ ok: true, user: db.users[email] });
});

// --- API: purchases (placeholder)
app.get('/api/purchases', (_req, res) => {
  const db = readDB();
  res.json({ ok: true, items: db.purchases || [] });
});

// --- Static frontend (Vite build)
const distDir = path.join(__dirname, 'frontend', 'dist');
if (fs.existsSync(distDir)) {
  app.use(express.static(distDir));
  app.get('*', (req, res) => {
    // only fall back for non-api
    if (req.path.startsWith('/api/')) return res.status(404).json({ ok: false, error: 'Not found' });
    res.sendFile(path.join(distDir, 'index.html'));
  });
} else {
  app.get('/', (_req, res) => res.send('Frontend not built yet. Run: cd frontend && npm ci && npm run build'));
}

app.listen(PORT, () => {
  console.log(`sms-activate listening on http://127.0.0.1:${PORT}`);
});
