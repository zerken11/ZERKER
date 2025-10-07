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
