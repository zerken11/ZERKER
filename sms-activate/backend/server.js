require('dotenv').config();
const express = require('express');
const session = require('express-session');
const helmet = require('helmet');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const path = require('path');

const auth = require('./auth');
const admin = require('./admin');
require('./db');

const PORT = process.env.PORT || 4000;
const SESSION_SECRET = process.env.SESSION_SECRET || 'change_me_now_please';
const ORIGINS = [
  'https://fakew.cyou',
  'http://localhost:5173',
  'http://localhost:4173',
  process.env.FRONTEND_ORIGIN || ''
].filter(Boolean);

const app = express();
app.disable('x-powered-by');
app.use(helmet());
app.use(cookieParser());
app.use(cors({ origin: ORIGINS, credentials: true }));
app.use(express.json({ limit: '1mb' }));

app.use(
  session({
    secret: SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    cookie: {
      sameSite: 'lax',
      secure: false,
      httpOnly: true,
      maxAge: 7 * 24 * 3600 * 1000
    }
  })
);

app.use('/api/auth', auth);
app.use('/api/admin', admin);
app.get('/api/ping', (req, res) => res.json({ pong: true }));

const distDir = path.join(__dirname, '..', 'frontend', 'dist');
app.use(express.static(distDir));
app.get('*', (req, res, next) => {
  const indexFile = path.join(distDir, 'index.html');
  res.sendFile(indexFile, (err) => {
    if (err) {
      next();
    }
  });
});

const server = app.listen(PORT, () => {
  console.log(`API listening on :${PORT}`);
});

module.exports = { app, server };
