import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { setToken, isTokenValid } from "../utils/auth";

export default function Login() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [err, setErr] = useState("");
  const nav = useNavigate();

  async function submit(e) {
    e.preventDefault();
    setErr("");
    try {
      const resp = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      const j = await resp.json();
      if (!resp.ok) {
        setErr(j.message || "Login failed");
        return;
      }
      if (j.token) {
        setToken(j.token);
        // immediate redirect to dashboard
        if (isTokenValid(j.token)) nav("/dashboard", { replace: true });
        else setErr("Token invalid/expired");
      } else {
        setErr("No token in response");
      }
    } catch (e) {
      setErr("Network error");
      console.error(e);
    }
  }

  return (
    <div className="page">
      <h1>Sign in</h1>
      <form onSubmit={submit}>
        <label>Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} />
        </label>
        <label>Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
        <button type="submit">Sign In</button>
      </form>
      {err && <p className="error">{err}</p>}
    </div>
  );
}
