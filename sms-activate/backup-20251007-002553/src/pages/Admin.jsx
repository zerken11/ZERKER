import { useEffect, useState } from "react";

export default function Admin() {
  const [stats, setStats] = useState(null);
  const [users, setUsers] = useState([]);
  const [target, setTarget] = useState("");
  const [amount, setAmount] = useState(0);

  async function fetchStats() {
    const token = localStorage.getItem("token");
    const res = await fetch("/api/admin/stats", { headers: { Authorization: "Bearer " + token } });
    if (!res.ok) return;
    const j = await res.json();
    setStats(j);
    setUsers(j.users || []);
  }

  useEffect(() => { fetchStats(); }, []);

  async function addBalance() {
    const token = localStorage.getItem("token");
    await fetch("/api/admin/add-balance", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ username: target, amount: Number(amount) })
    });
    fetchStats();
  }

  async function removeBalance() {
    const token = localStorage.getItem("token");
    await fetch("/api/admin/remove-balance", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ username: target, amount: Number(amount) })
    });
    fetchStats();
  }

  async function banUser(flag) {
    const token = localStorage.getItem("token");
    await fetch("/api/admin/ban", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ username: target, ban: flag })
    });
    fetchStats();
  }

  return (
    <div style={{ color: "lime", padding: 20 }}>
      <h2>Admin Console</h2>
      {stats && (
        <div>
          <p>Total users: {stats.totalUsers}</p>
          <p>Total purchases: {stats.totalPurchases}</p>
          <p>Total credit: {stats.totalCredit}</p>
        </div>
      )}
      <hr />
      <div>
        <input placeholder="target username" value={target} onChange={(e)=>setTarget(e.target.value)} />
        <input placeholder="amount" type="number" value={amount} onChange={(e)=>setAmount(e.target.value)} />
        <button onClick={addBalance}>Add Balance</button>
        <button onClick={removeBalance}>Remove Balance</button>
        <button onClick={()=>banUser(true)}>Ban</button>
        <button onClick={()=>banUser(false)}>Unban</button>
      </div>
      <hr/>
      <h3>Users</h3>
      <table style={{ width: "100%", color: "lime" }}>
        <thead><tr><th>Username</th><th>Role</th><th>Balance</th><th>Banned</th></tr></thead>
        <tbody>
          {users.map(u=>(
            <tr key={u.username}><td>{u.username}</td><td>{u.role}</td><td>{u.balance}</td><td>{u.banned? "yes":"no"}</td></tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
