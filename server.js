const express = require("express");
const bodyParser = require("body-parser");
const jwt = require("jsonwebtoken");
const path = require("path");
const fs = require("fs");

const app = express();
app.use(bodyParser.json());

const distPath = path.join(__dirname, "frontend", "dist");
app.use(express.static(distPath));

const JWT_SECRET = process.env.JWT_SECRET || "supersecret123";

// === LOGIN API ===
app.post("/api/login", (req, res) => {
  const { username, password } = req.body;

  if (username === "admin" && password === "1234") {
    const token = jwt.sign({ username }, JWT_SECRET, { expiresIn: "1h" });
    return res.json({ success: true, token });
  }

  res.status(401).json({ success: false, message: "Invalid credentials" });
});

// === VERIFY API ===
app.get("/api/verify", (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ valid: false });

  const token = authHeader.split(" ")[1];
  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) return res.status(401).json({ valid: false, expired: true });
    res.json({ valid: true, user: decoded.username });
  });
});

// let React handle routing
app.get("*", (req, res) => {
  const indexPath = path.join(distPath, "index.html");
  if (!fs.existsSync(indexPath)) {
    return res
      .status(503)
      .send("Frontend build missing. Run `npm run build` inside /frontend.");
  }
  res.sendFile(indexPath);
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Server running on ${PORT}`));
