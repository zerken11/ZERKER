#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$HOME/ZERKER/sms-activate"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

echo "== Writing backend server.js =="
cat > "$PROJECT_ROOT/server.js" <<'EOF'
const express = require("express");
const bodyParser = require("body-parser");
const jwt = require("jsonwebtoken");
const path = require("path");

const app = express();
app.use(bodyParser.json());

// serve React build
app.use(express.static(path.join(__dirname, "frontend/dist")));

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
  res.sendFile(path.join(__dirname, "frontend/dist/index.html"));
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Server running on ${PORT}`));
EOF

echo "== Backend deps =="
cd "$PROJECT_ROOT"
rm -rf node_modules package-lock.json
npm install express body-parser jsonwebtoken

echo "== Frontend setup =="
mkdir -p "$FRONTEND_DIR"
cd "$FRONTEND_DIR"

# scaffold vite app if not already
if [ ! -f package.json ] || ! grep -q '"build": "vite build"' package.json; then
  echo "Scaffolding new Vite React app..."
  rm -rf *
  npm create vite@latest . -- --template react <<EOF
y
EOF
  npm install
fi

mkdir -p src/pages

echo "== Writing React files =="

# App.jsx
cat > src/App.jsx <<'EOF'
import { Routes, Route, Navigate } from "react-router-dom";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";

function PrivateRoute({ children }) {
  const token = localStorage.getItem("token");
  return token ? children : <Navigate to="/" />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Login />} />
      <Route
        path="/dashboard"
        element={
          <PrivateRoute>
            <Dashboard />
          </PrivateRoute>
        }
      />
    </Routes>
  );
}
EOF

# Login.jsx
cat > src/pages/Login.jsx <<'EOF'
import { useState } from "react";
import { useNavigate } from "react-router-dom";

export default function Login() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const navigate = useNavigate();

  async function handleLogin(e) {
    e.preventDefault();
    try {
      const res = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });

      const data = await res.json();
      if (data.success) {
        localStorage.setItem("token", data.token);
        navigate("/dashboard");
      } else {
        alert("Login failed: " + (data.message || "try again"));
      }
    } catch (err) {
      console.error(err);
      alert("Server error");
    }
  }

  return (
    <div style={{ textAlign: "center", marginTop: "20vh", color: "lime" }}>
      <h1>HackerAI Matrix Login</h1>
      <form onSubmit={handleLogin}>
        <input
          type="text"
          placeholder="اسم المستخدم"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        /><br /><br />
        <input
          type="password"
          placeholder="كلمة المرور"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        /><br /><br />
        <button type="submit">تسجيل الدخول</button>
      </form>
    </div>
  );
}
EOF

# Dashboard.jsx
cat > src/pages/Dashboard.jsx <<'EOF'
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

export default function Dashboard() {
  const [user, setUser] = useState(null);
  const navigate = useNavigate();

  function logout() {
    localStorage.removeItem("token");
    navigate("/");
  }

  useEffect(() => {
    async function checkAuth() {
      const token = localStorage.getItem("token");
      if (!token) {
        logout();
        return;
      }

      try {
        const res = await fetch("/api/verify", {
          headers: { Authorization: "Bearer " + token },
        });
        const data = await res.json();

        if (!data.valid) {
          alert("Session expired, please login again.");
          logout();
        } else {
          setUser(data.user);
        }
      } catch (err) {
        console.error(err);
        logout();
      }
    }

    checkAuth();
    const interval = setInterval(checkAuth, 10000); // recheck every 10s
    return () => clearInterval(interval);
  }, []);

  return (
    <div style={{ color: "lime", textAlign: "center", marginTop: "20vh" }}>
      <h1>HackerAI Matrix Dashboard</h1>
      {user && <p>Logged in as: {user}</p>}
      <button onClick={logout} style={{ marginTop: "20px" }}>
        Logout
      </button>
    </div>
  );
}
EOF

echo "== Building frontend =="
npm install
npm install react-router-dom
npm run build

echo "== Restarting backend with PM2 =="
cd "$PROJECT_ROOT"
pm2 delete sms-activate || true
pm2 start server.js --name sms-activate

echo "== All done =="
pm2 ls

