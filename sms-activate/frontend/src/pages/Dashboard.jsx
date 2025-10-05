import { useEffect, useState } from 'react';
import { api } from '../lib/api';

export default function Dashboard() {
  const [me, setMe] = useState(null);

  useEffect(() => {
    (async () => {
      try {
        const profile = await api('/api/auth/me');
        setMe(profile);
      } catch (err) {
        console.error(err);
        window.location.href = '/login';
      }
    })();
  }, []);

  if (!me) {
    return <div className="p-6">Loading…</div>;
  }

  return (
    <div className="p-6 space-y-4">
      <h1 className="text-2xl font-bold">Welcome, {me.email}</h1>
      {me.role === 'admin' && (
        <a className="underline" href="/admin/credits">
          Go to Admin Credits
        </a>
      )}
      <button
        className="border px-3 py-1 rounded"
        onClick={async () => {
          await api('/api/auth/logout', { method: 'POST' });
          window.location.href = '/login';
        }}
      >
        Logout
      </button>
    </div>
  );
}
