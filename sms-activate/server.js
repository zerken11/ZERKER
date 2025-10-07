require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const jwt = require('jsonwebtoken');
const path = require('path');
const crypto = require('crypto');
const sqlite3 = require('sqlite3').verbose();

const app = express();
app.use(bodyParser.json());
app.use((req,res,next)=>{
  res.setHeader('Access-Control-Allow-Origin','*');
  res.setHeader('Access-Control-Allow-Headers','Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods','GET,POST,PUT,DELETE,OPTIONS');
  if(req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// serve static built frontend if exists
app.use(express.static(path.join(__dirname, 'frontend/dist')));

const PORT = process.env.PORT || 4000;
const JWT_SECRET = process.env.JWT_SECRET || 'fallbacksecret';
const JWT_EXPIRES = process.env.JWT_EXPIRES || '1h';

const tokenBlacklist = new Map();
function genJti(){ return crypto.randomBytes(16).toString('hex'); }
function blacklistToken(jti, exp){
  if(!jti || !exp) return;
  const ttl = Math.max(0, exp*1000 - Date.now());
  tokenBlacklist.set(jti, true);
  setTimeout(()=> tokenBlacklist.delete(jti), ttl + 2000);
}

// --- simple sqlite wrapper (promisified) ---
const DBFILE = path.join(__dirname, 'data.sqlite');
const db = new sqlite3.Database(DBFILE);
function run(sql, params=[]){ return new Promise((res,rej)=> db.run(sql, params, function(err){ if(err) rej(err); else res(this); })); }
function get(sql, params=[]){ return new Promise((res,rej)=> db.get(sql, params, (e,r)=> e?rej(e):res(r))); }
function all(sql, params=[]){ return new Promise((res,rej)=> db.all(sql, params, (e,r)=> e?rej(e):res(r))); }

(async function init(){
  await run(`CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY, username TEXT UNIQUE, balance REAL DEFAULT 0, banned INTEGER DEFAULT 0
  );`);
  await run(`CREATE TABLE IF NOT EXISTS purchases (
    id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, reason TEXT, created_at INTEGER DEFAULT (strftime('%s','now')),
    FOREIGN KEY(user_id) REFERENCES users(id)
  );`);
})().catch(err=>{ console.error('DB init failed', err); process.exit(1); });

// --- auth helpers ---
function signToken(payload){
  const jti = genJti();
  const token = jwt.sign(Object.assign({}, payload, { jti }), JWT_SECRET, { expiresIn: JWT_EXPIRES });
  return token;
}
function extractToken(req){
  const h = req.headers.authorization || '';
  if(h.startsWith('Bearer ')) return h.slice(7);
  return null;
}
async function verifyTokenMiddleware(req,res,next){
  const token = extractToken(req);
  if(!token) return res.status(401).json({ success:false, message:'No token' });
  let decoded;
  try{ decoded = jwt.verify(token, JWT_SECRET); } catch(e){ return res.status(401).json({ success:false, message:'Token invalid or expired' }); }
  if(decoded.jti && tokenBlacklist.has(decoded.jti)) return res.status(401).json({ success:false, message:'Token revoked' });
  // check ban
  try{
    const row = await get('SELECT banned FROM users WHERE username = ?', [decoded.username]);
    if(row && row.banned) return res.status(403).json({ success:false, message:'User banned' });
  }catch(err){ console.error('DB err check ban', err); }
  req.user = decoded;
  next();
}

// --- public health ---
app.get('/api/health', (req,res)=> res.json({ ok:true }));

// --- login ---
app.post('/api/login', async (req,res)=>{
  const { username, password } = req.body || {};
  if(!username || !password) return res.status(400).json({ success:false, message:'username+password required' });

  // quick admin stub (replace with real auth if you want)
  if(username === 'admin' && password === '1234'){
    try{ await run('INSERT OR IGNORE INTO users (username, balance, banned) VALUES (?, 0, 0)', ['admin']); }catch(e){ console.error(e); }
    const token = signToken({ username:'admin' });
    return res.json({ success:true, token });
  }

  // if user exists, sign token (passwordless for demo)
  const u = await get('SELECT * FROM users WHERE username = ?', [username]);
  if(u){
    const token = signToken({ username });
    return res.json({ success:true, token });
  }
  return res.status(401).json({ success:false, message:'Invalid credentials' });
});

// --- logout (blacklist jti) ---
app.post('/api/logout', verifyTokenMiddleware, (req,res)=>{
  const { jti, exp } = req.user || {};
  blacklistToken(jti, exp);
  res.json({ success:true, message:'Logged out' });
});

// --- verify ---
app.get('/api/verify', verifyTokenMiddleware, (req,res)=>{
  const { username, jti, exp, iat } = req.user || {};
  res.json({ success:true, username, jti, exp, iat });
});

// --- admin guard ---
async function requireAdmin(req,res,next){
  if(!req.user || req.user.username !== 'admin') return res.status(403).json({ success:false, message:'Admin only' });
  next();
}

// --- admin endpoints ---
app.post('/api/admin/add-balance', verifyTokenMiddleware, requireAdmin, async (req,res)=>{
  const { username, amount = 0, reason = 'admin-credit' } = req.body || {};
  if(!username || typeof amount !== 'number') return res.status(400).json({ success:false, message:'username, amount required' });
  await run('INSERT OR IGNORE INTO users (username) VALUES (?)', [username]);
  const user = await get('SELECT id, balance FROM users WHERE username = ?', [username]);
  const newBal = (user.balance || 0) + amount;
  await run('UPDATE users SET balance = ? WHERE id = ?', [newBal, user.id]);
  await run('INSERT INTO purchases (user_id, amount, reason) VALUES (?, ?, ?)', [user.id, amount, reason]);
  res.json({ success:true, username, balance: newBal });
});

app.post('/api/admin/remove-balance', verifyTokenMiddleware, requireAdmin, async (req,res)=>{
  const { username, amount = 0, reason = 'admin-debit' } = req.body || {};
  if(!username || typeof amount !== 'number') return res.status(400).json({ success:false, message:'username, amount required' });
  await run('INSERT OR IGNORE INTO users (username) VALUES (?)', [username]);
  const user = await get('SELECT id, balance FROM users WHERE username = ?', [username]);
  const newBal = (user.balance || 0) - amount;
  await run('UPDATE users SET balance = ? WHERE id = ?', [newBal, user.id]);
  await run('INSERT INTO purchases (user_id, amount, reason) VALUES (?, ?, ?)', [user.id, -Math.abs(amount), reason]);
  res.json({ success:true, username, balance: newBal });
});

app.post('/api/admin/ban-user', verifyTokenMiddleware, requireAdmin, async (req,res)=>{
  const { username } = req.body || {};
  if(!username) return res.status(400).json({ success:false, message:'username required' });
  await run('UPDATE users SET banned = 1 WHERE username = ?', [username]);
  res.json({ success:true, username, banned:true });
});

app.post('/api/admin/unban-user', verifyTokenMiddleware, requireAdmin, async (req,res)=>{
  const { username } = req.body || {};
  if(!username) return res.status(400).json({ success:false, message:'username required' });
  await run('UPDATE users SET banned = 0 WHERE username = ?', [username]);
  res.json({ success:true, username, banned:false });
});

app.get('/api/admin/stats', verifyTokenMiddleware, requireAdmin, async (req,res)=>{
  const totals = await get('SELECT COUNT(*) AS usersCount, SUM(balance) AS totalBalance FROM users');
  const purchasesRow = await get('SELECT COUNT(*) AS purchasesCount, SUM(amount) AS purchasesSum FROM purchases');
  res.json({
    success:true,
    users: totals?.usersCount || 0,
    totalBalance: parseFloat(totals?.totalBalance || 0),
    purchasesCount: purchasesRow?.purchasesCount || 0,
    purchasesSum: parseFloat(purchasesRow?.purchasesSum || 0)
  });
});

// user history
app.get('/api/users/:username/history', verifyTokenMiddleware, async (req,res)=>{
  const username = req.params.username;
  const user = await get('SELECT id, balance FROM users WHERE username = ?', [username]);
  if(!user) return res.status(404).json({ success:false, message:'User not found' });
  const purchases = await all('SELECT amount, reason, created_at FROM purchases WHERE user_id = ? ORDER BY created_at DESC LIMIT 200', [user.id]);
  res.json({ success:true, username, balance: parseFloat(user.balance||0), purchases });
});

// fallback to frontend index (SPA)
app.get('*', (req,res)=> res.sendFile(path.join(__dirname, 'frontend/dist/index.html')));

app.listen(PORT, ()=> console.log(`Server running on ${PORT}`));
