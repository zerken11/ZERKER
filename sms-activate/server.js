require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');

const auth = require('./auth');
const db = require('./db');

const app = express();
app.use(cors());
app.use(express.json());

// auth routes
app.use('/api/auth', auth);

// simple purchases route
app.get('/api/purchases', (req, res) => {
  res.json({ ok: true, items: [] });
});

// serve static frontend
app.use(express.static(path.join(__dirname, 'public')));
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public/index.html'));
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`✅ Server listening on :${PORT}`));
