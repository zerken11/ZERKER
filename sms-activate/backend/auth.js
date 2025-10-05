const express = require('express');
const bcrypt = require('bcrypt');
const db = require('./db');

const router = express.Router();

function findUserByEmail(email) {
  return db.prepare('SELECT * FROM users WHERE email = ?').get(email.toLowerCase());
}

function findUserById(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

function ensureCreditsRow(userId) {
  db.prepare('INSERT OR IGNORE INTO credits (user_id, balance) VALUES (?, 0)').run(userId);
}

router.post('/register', async (req, res) => {
  try {
    const { email, password, role } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ error: 'email and password required' });
    }

    const hash = await bcrypt.hash(password, 12);
    const stmt = db.prepare('INSERT INTO users (email, password_hash, role) VALUES (?, ?, ?)');
    const info = stmt.run(email.toLowerCase(), hash, role === 'admin' ? 'admin' : 'user');
    ensureCreditsRow(info.lastInsertRowid);

    return res.json({ ok: true });
  } catch (error) {
    if (String(error).includes('UNIQUE')) {
      return res.status(409).json({ error: 'email exists' });
    }
    console.error(error);
    return res.status(500).json({ error: 'server error' });
  }
});

router.post('/login', async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password required' });
  }

  const user = findUserByEmail(email);
  if (!user) {
    return res.status(401).json({ error: 'invalid credentials' });
  }

  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) {
    return res.status(401).json({ error: 'invalid credentials' });
  }

  req.session.userId = user.id;
  return res.json({ ok: true });
});

router.post('/logout', (req, res) => {
  req.session.destroy(() => res.json({ ok: true }));
});

router.get('/me', (req, res) => {
  if (!req.session.userId) {
    return res.status(401).json({ error: 'not logged in' });
  }

  const user = findUserById(req.session.userId);
  if (!user) {
    return res.status(401).json({ error: 'not logged in' });
  }

  return res.json({ id: user.id, email: user.email, role: user.role });
});

module.exports = router;
