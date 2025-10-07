#!/usr/bin/env bash
set -euo pipefail

# Run me from /home/client_28482_4/ZERKER/sms-activate
ROOT="$(pwd)"
FRONTEND="$ROOT/frontend"
BRANCH="feature/frontend-jwt-ui"
COMMIT_MSG="feat(frontend): add JWT login, dashboard, admin UI (auto-PR/merge)"

echo "Running from: $ROOT"
echo "Branch: $BRANCH"

# 1) create branch
git fetch origin
git checkout -B "$BRANCH"

# 2) ensure frontend src dir exists
mkdir -p "$FRONTEND/src/pages"
mkdir -p "$FRONTEND/src/assets"

# 3) write files (overwrites existing files with the same paths)
cat > "$FRONTEND/src/main.jsx" <<'EOF'
import React from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App";
import "./index.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
);
EOF

cat > "$FRONTEND/src/App.jsx" <<'EOF'
import React from "react";
import { Routes, Route, Navigate } from "react-router-dom";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Admin from "./pages/Admin";
import { getToken, isTokenValid } from "./utils/auth";

function ProtectedRoute({ children }) {
  const token = getToken();
  if (!token || !isTokenValid(token)) {
    return <Navigate to="/login" replace />;
  }
  return children;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/dashboard"
        element={
          <ProtectedRoute>
            <Dashboard />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin"
        element={
          <ProtectedRoute>
            <Admin />
          </ProtectedRoute>
        }
      />
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
EOF

mkdir -p "$FRONTEND/src/utils"
cat > "$FRONTEND/src/utils/auth.js" <<'EOF'
// small JWT helpers (no external libs). Stores token in localStorage under "token".
export function setToken(token) {
  localStorage.setItem("token", token);
}
export function getToken() {
  return localStorage.getItem("token");
}
export function removeToken() {
  localStorage.removeItem("token");
}
export function decodeToken(token) {
  try {
    const payload = token.split(".")[1];
    return JSON.parse(atob(payload));
  } catch (e) {
    return null;
  }
}
export function isTokenValid(token) {
  const d = decodeToken(token);
  if (!d || !d.exp) return false;
  // exp is seconds since epoch
  return Date.now() < d.exp * 1000;
}
export function getUsernameFromToken(token) {
  const d = decodeToken(token);
  return d?.username || null;
}
EOF

cat > "$FRONTEND/src/pages/Login.jsx" <<'EOF'
import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { setToken, isTokenValid } from "../utils/auth";

export default function Login() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [err, setErr] = useState("");
  const nav = useNavigate();

  async function submit(e) {
    e.preventDefault();
    setErr("");
    try {
      const resp = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      const j = await resp.json();
      if (!resp.ok) {
        setErr(j.message || "Login failed");
        return;
      }
      if (j.token) {
        setToken(j.token);
        // immediate redirect to dashboard
        if (isTokenValid(j.token)) nav("/dashboard", { replace: true });
        else setErr("Token invalid/expired");
      } else {
        setErr("No token in response");
      }
    } catch (e) {
      setErr("Network error");
      console.error(e);
    }
  }

  return (
    <div className="page">
      <h1>Sign in</h1>
      <form onSubmit={submit}>
        <label>Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} />
        </label>
        <label>Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
        <button type="submit">Sign In</button>
      </form>
      {err && <p className="error">{err}</p>}
    </div>
  );
}
EOF

cat > "$FRONTEND/src/pages/Dashboard.jsx" <<'EOF'
import React, { useEffect, useState, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { getToken, removeToken, decodeToken, isTokenValid, getUsernameFromToken } from "../utils/auth";

function api(path, opts = {}) {
  const token = getToken();
  return fetch(path, {
    headers: Object.assign({ "Content-Type": "application/json", Authorization: token ? `Bearer ${token}` : "" }, opts.headers || {}),
    ...opts,
  }).then(async (r) => {
    const text = await r.text();
    try { return { ok: r.ok, json: JSON.parse(text), status: r.status }; } catch { return { ok: r.ok, text, status: r.status }; }
  });
}

export default function Dashboard() {
  const [user, setUser] = useState(null);
  const [history, setHistory] = useState([]);
  const nav = useNavigate();

  const logout = useCallback((reason) => {
    removeToken();
    if (reason) console.log("auto-logout:", reason);
    nav("/login", { replace: true });
  }, [nav]);

  useEffect(() => {
    const token = getToken();
    if (!token) return logout("no token");
    if (!isTokenValid(token)) return logout("expired");

    // auto-expire watch: check every 3s
    const iv = setInterval(() => {
      const t = getToken();
      if (!t || !isTokenValid(t)) {
        clearInterval(iv);
        logout("expired");
      }
    }, 3000);

    // fetch user info & history
    (async () => {
      const username = getUsernameFromToken(token);
      setUser(username);
      const r = await api(`/api/users/${username}/history`);
      if (r.ok) setHistory(r.json.purchases || []);
    })();

    return () => clearInterval(iv);
  }, [logout]);

  return (
    <div className="page">
      <header style={{display:"flex",justifyContent:"space-between"}}>
        <h2>Dashboard</h2>
        <div>
          <button onClick={() => { removeToken(); nav("/login"); }}>Logout</button>
        </div>
      </header>

      <section>
        <p>Signed in as: <strong>{user}</strong></p>
        <h3>Purchase history</h3>
        <ul>
          {history.length===0 && <li>No purchases yet</li>}
          {history.map((p, i) => (
            <li key={i}>
              {new Date((p.created_at||0)*1000).toLocaleString()} — {p.reason} — {p.amount}
            </li>
          ))}
        </ul>
      </section>

      <section>
        <p><a href="/admin">Admin panel</a> (admin only)</p>
      </section>
    </div>
  );
}
EOF

cat > "$FRONTEND/src/pages/Admin.jsx" <<'EOF'
import React, { useState } from "react";
import { getToken } from "../utils/auth";

const api = async (path, opts = {}) => {
  const token = getToken();
  const r = await fetch(path, Object.assign({
    method: opts.method || "POST",
    headers: { "Content-Type": "application/json", Authorization: token ? `Bearer ${token}` : "" },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  }, opts.fetchOpts || {}));
  const j = await r.json().catch(()=>null);
  return { ok: r.ok, status: r.status, json: j };
};

export default function Admin() {
  const [username, setUsername] = useState("");
  const [amount, setAmount] = useState(0);
  const [out, setOut] = useState("");

  async function doAction(action, body) {
    setOut("...");
    const r = await api(`/api/admin/${action}`, { body });
    setOut(JSON.stringify(r.json) || `HTTP ${r.status}`);
  }

  return (
    <div className="page">
      <h2>Admin</h2>
      <div className="card">
        <h4>Add balance</h4>
        <input placeholder="username" value={username} onChange={e=>setUsername(e.target.value)} />
        <input type="number" value={amount} onChange={e=>setAmount(Number(e.target.value))} />
        <button onClick={()=>doAction("add-balance", { username, amount })}>Add</button>
      </div>

      <div className="card">
        <h4>Remove balance</h4>
        <input placeholder="username" value={username} onChange={e=>setUsername(e.target.value)} />
        <input type="number" value={amount} onChange={e=>setAmount(Number(e.target.value))} />
        <button onClick={()=>doAction("remove-balance", { username, amount })}>Remove</button>
      </div>

      <div className="card">
        <h4>Ban / Unban</h4>
        <input placeholder="username" value={username} onChange={e=>setUsername(e.target.value)} />
        <button onClick={()=>doAction("ban-user", { username })}>Ban</button>
        <button onClick={()=>doAction("unban-user", { username })}>Unban</button>
      </div>

      <div className="card">
        <h4>Stats</h4>
        <button onClick={()=>doAction("stats", {})}>Get stats</button>
      </div>

      <pre style={{whiteSpace:"pre-wrap"}}>{out}</pre>
    </div>
  );
}
EOF

cat > "$FRONTEND/src/index.css" <<'EOF'
body { font-family: system-ui, sans-serif; padding: 24px; background:#f6f8fa; color:#111; }
.page { max-width:900px; margin: 0 auto; background:white; padding:20px; border-radius:6px; box-shadow:0 6px 24px rgba(0,0,0,0.06) }
input { display:block; margin:8px 0 12px; padding:8px; width:100%; box-sizing:border-box; }
button { padding:8px 12px; margin-right:8px; }
.card { border:1px solid #eee; padding:12px; margin:12px 0; border-radius:6px; background:#fcfcfd; }
.error { color:crimson; }
EOF

# 4) commit files
git add "$FRONTEND/src" || true

# 5) install react-router-dom in frontend (updates frontend package.json & package-lock)
echo "Installing react-router-dom in frontend (this will modify frontend/package.json and package-lock.json)..."
cd "$FRONTEND"
npm install react-router-dom --no-audit --no-fund
cd "$ROOT"

git add "$FRONTEND/package.json" "$FRONTEND/package-lock.json" || true

# 6) commit & push
git commit -m "$COMMIT_MSG" || { echo "Nothing to commit"; }
git push -u origin "$BRANCH"

# 7) create PR and merge via gh
echo "Creating PR..."
gh pr create --title "feat(frontend): JWT login & admin UI" \
  --body "Adds frontend pages for JWT login, dashboard, admin panel. Auto-logout when token expires." \
  --base main --head "$BRANCH" || true

echo "Attempting to auto-merge PR..."
gh pr merge --merge --delete-branch --subject "chore(frontend): merge JWT UI" --body "Merging frontend JWT UI" || {
  echo "Automatic merge failed (maybe requires review). Opening PR in browser..."
  gh pr view --web || echo "Open PR manually: https://github.com/$(git config --get remote.origin.url | sed -e 's#.*github.com[:/]\(.*\)\.git#\1#')/pulls"
}

echo "Done. If CI runs, watch it in GitHub Actions or run `gh run list`."

