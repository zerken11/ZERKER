// small JWT helpers (no external libs). Stores token in localStorage under "token".
export function setToken(token) {
  localStorage.setItem("token", token);
}
export function getToken() {
  return localStorage.getItem("token");
}
export function removeToken() {
  localStorage.removeItem("token");
}
export function decodeToken(token) {
  try {
    const payload = token.split(".")[1];
    return JSON.parse(atob(payload));
  } catch (e) {
    return null;
  }
}
export function isTokenValid(token) {
  const d = decodeToken(token);
  if (!d || !d.exp) return false;
  // exp is seconds since epoch
  return Date.now() < d.exp * 1000;
}
export function getUsernameFromToken(token) {
  const d = decodeToken(token);
  return d?.username || null;
}
