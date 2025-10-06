import { useEffect, useState } from 'react';
import { api } from '../lib/api';

export default function AdminCredits(){
  const [users,setUsers]=useState([]);
  const [email,setEmail]=useState('');
  const [amount,setAmount]=useState('');
  const [msg,setMsg]=useState('');

  useEffect(()=>{ load(); },[]);
  async function load(){ try{ const d=await api('/api/admin/users'); setUsers(d.users||[]); } catch{} }

  async function addCredit(){
    try{
      const d=await api('/api/admin/add-credit',{method:'POST',body:JSON.stringify({email,amount})});
      setMsg('Credit updated'); load();
    }catch(e){ setMsg(e.message); }
  }

  return (
    <div className="p-6">
      <h1 className="text-xl font-bold mb-4">Admin Credits</h1>
      <div className="space-x-2 mb-4">
        <input className="border p-2" placeholder="User email" value={email} onChange={e=>setEmail(e.target.value)} />
        <input className="border p-2" placeholder="Amount" value={amount} onChange={e=>setAmount(e.target.value)} />
        <button className="border p-2" onClick={addCredit}>Add Credit</button>
      </div>
      {msg && <div className="text-sm">{msg}</div>}
      <table className="border">
        <thead><tr><th>Email</th><th>Credits</th></tr></thead>
        <tbody>
          {users.map(u=><tr key={u.email}><td>{u.email}</td><td>{u.credits}</td></tr>)}
        </tbody>
      </table>
    </div>
  );
}
