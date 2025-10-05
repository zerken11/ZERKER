const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const DB_PATH = path.join(__dirname, '..', 'data', 'db.json');

let writeQueue = Promise.resolve();

async function init() {
  await fsp.mkdir(path.dirname(DB_PATH), { recursive: true });
  try { await fsp.access(DB_PATH, fs.constants.F_OK); }
  catch { await fsp.writeFile(DB_PATH, JSON.stringify({ users: {}, activations: {}, tokens: {} }, null, 2)); }
}

async function _read() {
  const raw = await fsp.readFile(DB_PATH, 'utf8');
  return JSON.parse(raw);
}
function _enqueueWrite(data) {
  writeQueue = writeQueue.then(() => fsp.writeFile(DB_PATH, JSON.stringify(data, null, 2)));
  return writeQueue;
}

async function upsertUser(user) {
  const db = await _read();
  const id = String(user.id);
  const existing = db.users[id] || {};
  const merged = { balance: 0, createdAt: existing.createdAt || new Date().toISOString(), ...existing, ...user, id };
  db.users[id] = merged;
  await _enqueueWrite(db);
  return merged;
}
async function getUser(id) { const db = await _read(); return db.users[String(id)] || null; }
async function getUserByUsername(username) {
  const db = await _read();
  return Object.values(db.users).find(u => (u.username_local||'').toLowerCase() === String(username).toLowerCase()) || null;
}
async function addCredit(id, amount) {
  const db = await _read();
  const key = String(id);
  db.users[key] = db.users[key] || { id: key, balance: 0, createdAt: new Date().toISOString() };
  db.users[key].balance = (db.users[key].balance || 0) + amount;
  await _enqueueWrite(db); return db.users[key].balance;
}
async function deductCredit(id, amount) {
  const db = await _read();
  const key = String(id);
  if (!db.users[key]) throw new Error('USER_NOT_FOUND');
  const bal = db.users[key].balance || 0;
  if (bal < amount) throw new Error('INSUFFICIENT_FUNDS');
  db.users[key].balance = bal - amount;
  await _enqueueWrite(db); return db.users[key].balance;
}
async function listUsers(limit = 50) {
  const db = await _read();
  return Object.values(db.users).sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt)).slice(0, limit);
}
async function setPasswordHash(id, username_local, hash) {
  const db = await _read();
  const key = String(id);
  db.users[key] = db.users[key] || { id: key, balance: 0, createdAt: new Date().toISOString() };
  db.users[key].username_local = username_local;
  db.users[key].passHash = hash;
  await _enqueueWrite(db);
  return db.users[key];
}

async function saveActivation(act) { const db = await _read(); db.activations[act.id] = act; await _enqueueWrite(db); }
async function getActivation(id) { const db = await _read(); return db.activations[id] || null; }
async function listUserActivations(uid, limit=10) {
  const db = await _read();
  return Object.values(db.activations).filter(a=>String(a.userId)===String(uid)).sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt)).slice(0,limit);
}
async function updateActivation(id, patch) {
  const db = await _read();
  db.activations[id] = { ...(db.activations[id]||{}), ...patch };
  await _enqueueWrite(db);
  return db.activations[id];
}

async function createToken(token, uid, ttlMs=1000*60*60*24*7) {
  const db = await _read();
  db.tokens[token] = { uid, createdAt: Date.now(), expiresAt: Date.now()+ttlMs };
  await _enqueueWrite(db);
}
async function resolveToken(token) {
  const db = await _read();
  const t = db.tokens[token];
  if (!t) return null;
  if (t.expiresAt && Date.now()>t.expiresAt) return null;
  return t.uid;
}

module.exports = {
  init, upsertUser, getUser, getUserByUsername, addCredit, deductCredit, listUsers, setPasswordHash,
  saveActivation, getActivation, listUserActivations, updateActivation,
  createToken, resolveToken
};
