import { useState } from 'react';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');

  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      const r = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });
      const d = await r.json();
      if (!r.ok || d.ok === false) throw new Error(d.error || 'Login failed');
      localStorage.setItem('token', d.token);
      location.href = '/dashboard';
    } catch (e) {
      setErr(e.message);
    }
  }

  return (
    <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 24 }}>
      <form onSubmit={submit} style={{ width: 360, display: 'grid', gap: 12, border: '1px solid #ddd', borderRadius: 12, padding: 16 }}>
        <h1 style={{ margin: 0 }}>Sign in</h1>
        <input placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} style={{ padding: 8 }} />
        <input type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} style={{ padding: 8 }} />
        {err && <div style={{ color: 'crimson', fontSize: 12 }}>{err}</div>}
        <button type="submit" style={{ padding: 10, fontWeight: 600 }}>Login</button>
        <small>Tip: admin is <code>ADMIN_EMAIL / ADMIN_PASSWORD</code> from server env.</small>
      </form>
    </div>
  );
}
