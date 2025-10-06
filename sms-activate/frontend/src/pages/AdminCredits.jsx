import { useEffect, useState } from 'react';
import { api } from '../lib/api';

export default function AdminCredits() {
  const [me, setMe] = useState(null);
  const [users, setUsers] = useState([]);
  const [email, setEmail] = useState('');
  const [amount, setAmount] = useState('');
  const [msg, setMsg] = useState('');

  useEffect(() => {
    (async () => {
      try {
        const info = await api('/api/me');
        setMe(info);
        if (info.role !== 'admin') return (location.href = '/');
        load();
      } catch {
        location.href = '/';
      }
    })();
  }, []);

  async function load() {
    try {
      const d = await api('/api/admin/users');
      setUsers(d.users || []);
    } catch (e) {
      setMsg(e.message);
    }
  }

  async function addCredit() {
    setMsg('');
    try {
      await api('/api/admin/add-credit', { method: 'POST', body: JSON.stringify({ email, amount }) });
      setMsg('Credit updated');
      setEmail(''); setAmount('');
      load();
    } catch (e) { setMsg(e.message); }
  }

  if (!me) return <div style={{ padding: 16 }}>Loading…</div>;

  return (
    <div style={{ padding: 16, display: 'grid', gap: 12 }}>
      <div><a href="/dashboard">← Back</a></div>
      <h2>Admin: Credits</h2>
      <div style={{ display: 'flex', gap: 8 }}>
        <input placeholder="user email" value={email} onChange={e => setEmail(e.target.value)} />
        <input placeholder="amount (+/-)" value={amount} onChange={e => setAmount(e.target.value)} />
        <button onClick={addCredit}>Apply</button>
      </div>
      {msg && <div>{msg}</div>}
      <table border="1" cellPadding="6" style={{ borderCollapse: 'collapse', maxWidth: 640 }}>
        <thead><tr><th>Email</th><th>Credits</th><th>Role</th></tr></thead>
        <tbody>
          {users.map(u => <tr key={u.email}><td>{u.email}</td><td>{u.credits}</td><td>{u.role || 'user'}</td></tr>)}
        </tbody>
      </table>
    </div>
  );
}
