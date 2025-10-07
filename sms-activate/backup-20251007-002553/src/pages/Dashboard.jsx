import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

export default function Dashboard() {
  const [user, setUser] = useState(null);
  const navigate = useNavigate();

  function logout() {
    localStorage.removeItem("token");
    navigate("/");
  }

  useEffect(() => {
    async function checkAuth() {
      const token = localStorage.getItem("token");
      if (!token) {
        logout();
        return;
      }

      const res = await fetch("/api/verify", {
        headers: { Authorization: "Bearer " + token },
      });
      const data = await res.json();

      if (!data.valid) {
        localStorage.removeItem("token");
        navigate("/");
      } else {
        // server returns { valid: true, user: { username, role, banned } }
        setUser(data.user);
      }
    }

    checkAuth();
    const interval = setInterval(checkAuth, 10000); // recheck every 10s
    return () => clearInterval(interval);
  }, [navigate]);

  return (
    <div style={{ color: "lime", textAlign: "center", marginTop: "20vh" }}>
      <h1>HackerAI Matrix Dashboard</h1>
      {user && <p>Logged in as: {user.username}</p>}
      {user && user.role === "admin" && (
        <p><a href="/admin">Go to Admin Console</a></p>
      )}
      <button onClick={logout} style={{ marginTop: "20px" }}>
        Logout
      </button>
    </div>
  );
}
