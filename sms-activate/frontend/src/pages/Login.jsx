import { useState } from 'react';

export default function Login(){
  const [email,setEmail]=useState('');
  const [password,setPassword]=useState('');
  const [err,setErr]=useState('');

  const submit=async(e)=>{ e.preventDefault(); setErr('');
    try{
      const r=await fetch('/api/auth/login',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({email,password})
      });
      const data=await r.json();
      if(!r.ok) throw new Error(data.error||'login failed');
      localStorage.setItem('token', data.token);
      location.href='/dashboard';
    }catch(e){ setErr(e.message); }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      <form onSubmit={submit} className="w-full max-w-sm space-y-4 border p-6 rounded-xl">
        <h1 className="text-2xl font-bold">Login</h1>
        <input className="w-full border p-2 rounded" placeholder="Email"
          value={email} onChange={e=>setEmail(e.target.value)} />
        <input className="w-full border p-2 rounded" type="password" placeholder="Password"
          value={password} onChange={e=>setPassword(e.target.value)} />
        {err && <div className="text-red-600 text-sm">{err}</div>}
        <button className="w-full border p-2 rounded font-semibold" type="submit">Sign in</button>
        <a className="block text-sm underline" href="/signup">Need an account? Sign up</a>
      </form>
    </div>
  );
}
