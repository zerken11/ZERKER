import { useEffect, useState } from 'react';
import { api } from '../lib/api';

export default function AdminCredits() {
  const [me, setMe] = useState(null);
  const [users, setUsers] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const profile = await api('/api/auth/me');
        setMe(profile);
        if (profile.role !== 'admin') {
          window.location.href = '/dashboard';
          return;
        }
        const rows = await api('/api/admin/users');
        setUsers(rows);
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const addCredits = async (userId, delta) => {
    try {
      const result = await api('/api/admin/credits/add', {
        method: 'POST',
        body: { userId, amount: Number(delta) }
      });
      setUsers((existing) =>
        existing.map((user) => (user.id === userId ? { ...user, balance: result.balance } : user))
      );
    } catch (err) {
      alert(err.message);
    }
  };

  if (loading) {
    return <div className="p-6">Loading…</div>;
  }

  if (error) {
    return <div className="p-6 text-red-600">{error}</div>;
  }

  return (
    <div className="p-6 space-y-6">
      <h1 className="text-2xl font-bold">Admin: Credits</h1>
      <table className="w-full border bg-white">
        <thead>
          <tr className="bg-gray-100">
            <th className="p-2 text-left">ID</th>
            <th className="p-2 text-left">Email</th>
            <th className="p-2">Role</th>
            <th className="p-2">Balance</th>
            <th className="p-2">+/-</th>
          </tr>
        </thead>
        <tbody>
          {users.map((user) => (
            <tr key={user.id} className="border-t">
              <td className="p-2">{user.id}</td>
              <td className="p-2">{user.email}</td>
              <td className="p-2 text-center">{user.role}</td>
              <td className="p-2 text-center">{user.balance}</td>
              <td className="p-2 text-center space-x-2">
                <button className="border px-2 py-1 rounded" onClick={() => addCredits(user.id, 10)}>
                  +10
                </button>
                <button className="border px-2 py-1 rounded" onClick={() => addCredits(user.id, 100)}>
                  +100
                </button>
                <button className="border px-2 py-1 rounded" onClick={() => addCredits(user.id, -10)}>
                  -10
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
