# (paste content, save Ctrl+O Enter, exit Ctrl+X)
mkdir -p sms-activate/frontend/src/pages

cat > sms-activate/frontend/src/pages/Dashboard.jsx <<'JS'
import React, { useEffect, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';

function decodeToken(token){
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    return JSON.parse(atob(parts[1]));
  } catch { return null; }
}

export default function Dashboard(){
  const nav = useNavigate();
  const [info, setInfo] = useState(null);
  const [countdown, setCountdown] = useState(null);

  useEffect(()=> {
    const token = localStorage.getItem('token');
    if (!token) return nav('/login', { replace: true });

    const t = decodeToken(token);
    if (!t) { localStorage.removeItem('token'); return nav('/login'); }
    const expiryMs = (t.exp * 1000) - Date.now();
    setCountdown(Math.max(0, Math.floor(expiryMs/1000)));

    const iv = setInterval(()=> {
      setCountdown(c => {
        if (c <= 1) {
          localStorage.removeItem('token');
          nav('/login', { replace: true });
          clearInterval(iv);
          return 0;
        }
        return c - 1;
      });
    }, 1000);

    // verify token against API
    fetch('/api/verify', { headers: { Authorization: 'Bearer ' + token }})
      .then(r => {
        if (!r.ok) throw new Error('token invalid');
        return r.json();
      })
      .then(j => setInfo(j))
      .catch(()=> {
        localStorage.removeItem('token');
        nav('/login', { replace: true });
      });

    return ()=> clearInterval(iv);
  }, []);

  function logout(){
    const token = localStorage.getItem('token');
    if (token) {
      fetch('/api/logout', { method: 'POST', headers: { Authorization: 'Bearer ' + token }});
    }
    localStorage.removeItem('token');
    nav('/login');
  }

  if (!info) return <div>Loading...</div>;

  return (
    <div style={{padding:20}}>
      <h2>Dashboard — {info.username}</h2>
      <div>Token expires in: <strong>{countdown}s</strong></div>
      <div style={{marginTop:10}}>
        <button onClick={logout}>Logout</button>
        <Link to="/admin" style={{marginLeft:10}}>Admin</Link>
      </div>
      <div style={{marginTop:20}}>
        <h3>Quick actions</h3>
        <p>Use Admin for balances / bans / history.</p>
      </div>
    </div>
  );
}
JS

