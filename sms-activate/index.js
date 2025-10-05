<!doctype html>
};


// Telegram handler
window.onTelegramAuth = async (user) => {
const r = await fetch('/api/login-tg', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(user) });
const d = await r.json();
if (d.ok) { toast('Telegram login ✔'); fetchMe(); } else toast('Telegram login failed');
};


// Logout
document.getElementById('logoutBtn').onclick = async () => {
await fetch('/api/logout', { method: 'POST' });
toast('Logged out');
showLoggedOut();
};


// Buy number
document.getElementById('buyBtn').onclick = async () => {
const service = document.getElementById('svc').value.trim() || 'wa';
const country = document.getElementById('ctry').value.trim() || '6';
const r = await fetch('/api/buy-number', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ service, country }) });
const d = await r.json();
if (d.ok) { document.getElementById('buyMsg').textContent = `Number: ${d.number.phone} (req ${d.number.requestId || '-'})`; toast('Number requested'); loadPurchases(); }
else { document.getElementById('buyMsg').textContent = `Error: ${d.error}`; toast('Failed'); }
};


async function loadPurchases() {
const r = await fetch('/api/purchases');
const d = await r.json();
const tb = document.getElementById('purchTbody');
tb.innerHTML = '';
if (d.ok) {
d.items.forEach((row, i) => {
const tr = document.createElement('tr');
tr.innerHTML = `<td class="py-1 opacity-70">${i+1}</td>
<td>${row.service}</td>
<td>${row.country}</td>
<td class="font-mono">${row.phone || '-'}</td>
<td>${row.status}</td>
<td class="opacity-70">${row.created_at}</td>`;
tb.appendChild(tr);
});
}
}


document.getElementById('refreshPurch').onclick = loadPurchases;


// initial load
fetchMe().then(loadPurchases);
</script>
</body>
</html>
