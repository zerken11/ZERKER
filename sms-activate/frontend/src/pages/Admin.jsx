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
