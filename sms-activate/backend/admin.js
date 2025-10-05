const express = require('express');
const db = require('./db');

const router = express.Router();

function requireAuth(req, res, next) {
  if (!req.session?.userId) {
    return res.status(401).json({ error: 'not logged in' });
  }
  next();
}

function requireAdmin(req, res, next) {
  const record = db.prepare('SELECT role FROM users WHERE id = ?').get(req.session.userId);
  if (!record || record.role !== 'admin') {
    return res.status(403).json({ error: 'admin only' });
  }
  next();
}

router.get('/users', requireAuth, requireAdmin, (req, res) => {
  const rows = db
    .prepare(`
      SELECT u.id, u.email, u.role, IFNULL(c.balance, 0) AS balance, u.created_at
      FROM users u
      LEFT JOIN credits c ON c.user_id = u.id
      ORDER BY u.id DESC
    `)
    .all();

  res.json(rows);
});

router.post('/credits/add', requireAuth, requireAdmin, (req, res) => {
  const { userId, amount } = req.body || {};
  const parsedAmount = parseInt(amount, 10);

  if (!userId || Number.isNaN(parsedAmount)) {
    return res.status(400).json({ error: 'userId and integer amount required' });
  }

  const exists = db.prepare('SELECT id FROM users WHERE id = ?').get(userId);
  if (!exists) {
    return res.status(404).json({ error: 'user not found' });
  }

  db.prepare('INSERT OR IGNORE INTO credits (user_id, balance) VALUES (?, 0)').run(userId);
  db.prepare(
    'UPDATE credits SET balance = balance + ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?'
  ).run(parsedAmount, userId);

  const balanceRow = db.prepare('SELECT balance FROM credits WHERE user_id = ?').get(userId);
  res.json({ ok: true, balance: balanceRow.balance });
});

router.get('/credits/:userId', requireAuth, requireAdmin, (req, res) => {
  const row = db.prepare('SELECT balance FROM credits WHERE user_id = ?').get(req.params.userId);
  res.json({ balance: row?.balance ?? 0 });
});

module.exports = router;
