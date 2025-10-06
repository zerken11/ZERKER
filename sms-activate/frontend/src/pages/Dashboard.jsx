import { useEffect, useState } from 'react';
import { api } from '../lib/api';

export default function Dashboard(){
  const [me,setMe]=useState(null);
  useEffect(()=>{ (async()=>{
    try{ setMe(await api('/api/me')); } catch { location.href='/login'; }
  })(); },[]);
  if(!me) return <div className="p-6">Loading…</div>;
  return <div className="p-6">Welcome, {me.email}</div>;
}
