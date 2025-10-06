import { useEffect, useState } from 'react';
import { api } from '../lib/api';

export default function Dashboard() {
  const [me, setMe] = useState(null);
  const [items, setItems] = useState([]);

  useEffect(() => {
    (async () => {
      try {
        const info = await api('/api/me');
        setMe(info);
        const purch = await api('/api/purchases');
        setItems(purch.items || []);
      } catch {
        location.href = '/';
      }
    })();
  }, []);

  if (!me) return <div style={{ padding: 16 }}>Loading…</div>;

  return (
    <div style={{ padding: 16, display: 'grid', gap: 12 }}>
      <div>Welcome, <b>{me.email}</b> — credits: <b>{me.credits}</b>{me.role === 'admin' ? ' (admin)' : ''}</div>
      <div style={{ display: 'flex', gap: 8 }}>
        <button onClick={() => { localStorage.removeItem('token'); fetch('/api/logout', { method: 'POST' }); location.href = '/'; }}>
          Logout
        </button>
        {me.role === 'admin' && <a href="/admin">Go to Admin</a>}
      </div>
      <h3>Your purchases</h3>
      <table border="1" cellPadding="6" style={{ borderCollapse: 'collapse', maxWidth: 640 }}>
        <thead><tr><th>#</th><th>Service</th><th>Phone</th></tr></thead>
        <tbody>
          {items.length === 0 && <tr><td colSpan={3} style={{ opacity: 0.7 }}>No purchases yet</td></tr>}
          {items.map((r, i) => <tr key={i}><td>{i + 1}</td><td>{r.service || '-'}</td><td>{r.phone || '-'}</td></tr>)}
        </tbody>
      </table>
    </div>
  );
}
