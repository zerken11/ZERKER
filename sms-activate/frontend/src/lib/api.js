export async function api(path, opts = {}) {
  const token = localStorage.getItem('token');
  const headers = { ...(opts.headers||{}), 'Content-Type':'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(path, { ...opts, headers });
  const data = await res.json().catch(()=> ({}));
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}
