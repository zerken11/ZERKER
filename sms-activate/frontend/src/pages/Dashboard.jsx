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

      try {
        const res = await fetch("/api/verify", {
          headers: { Authorization: "Bearer " + token },
        });
        const data = await res.json();

        if (!data.valid) {
          alert("Session expired, please login again.");
          logout();
        } else {
          setUser(data.user);
        }
      } catch (err) {
        console.error(err);
        logout();
      }
    }

    checkAuth();
    const interval = setInterval(checkAuth, 10000); // recheck every 10s
    return () => clearInterval(interval);
  }, []);

  return (
    <div style={{ color: "lime", textAlign: "center", marginTop: "20vh" }}>
      <h1>HackerAI Matrix Dashboard</h1>
      {user && <p>Logged in as: {user}</p>}
      <button onClick={logout} style={{ marginTop: "20px" }}>
        Logout
      </button>
    </div>
  );
}
