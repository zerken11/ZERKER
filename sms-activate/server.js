const express = require('express');
const path = require('path');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// API routes
app.use('/api/auth', require('./auth'));
app.use('/api/oauth', require('./oauth'));
app.use('/api/db', require('./db'));

// Example purchases endpoint
app.get('/api/purchases', (req,res)=> res.json({ok:true,items:[]}));

// Serve frontend
const distPath = path.join(__dirname,'frontend','dist');
app.use(express.static(distPath));
app.get('*',(req,res)=> res.sendFile(path.join(distPath,'index.html')));

const PORT = process.env.PORT || 4000;
app.listen(PORT, ()=> console.log(`Server running on ${PORT}`));
