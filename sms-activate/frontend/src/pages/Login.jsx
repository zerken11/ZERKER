import { useState } from 'react';
import { api } from '../lib/api';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = async (event) => {
    event.preventDefault();
    setError('');
    try {
      await api('/api/auth/login', { method: 'POST', body: { email, password } });
      window.location.href = '/dashboard';
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      <form onSubmit={handleSubmit} className="w-full max-w-sm space-y-4 border p-6 rounded-xl bg-white">
        <h1 className="text-2xl font-bold text-center">Login</h1>
        <input
          className="w-full border p-2 rounded"
          placeholder="Email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
        <input
          className="w-full border p-2 rounded"
          type="password"
          placeholder="Password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />
        {error && <div className="text-red-600 text-sm">{error}</div>}
        <button className="w-full border p-2 rounded font-semibold" type="submit">
          Sign in
        </button>
        <a className="block text-sm underline text-center" href="/signup">
          Need an account? Sign up
        </a>
      </form>
    </div>
  );
}
