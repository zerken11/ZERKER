const $ = (sel)=>document.querySelector(sel);
const $$ = (sel)=>Array.from(document.querySelectorAll(sel));
const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));

let currentLang = 'en';
let translations = {};
let config = {};

async function api(path, opts={}) {
  const r = await fetch(path, { credentials:'include', headers:{'Content-Type':'application/json'}, ...opts });
  if (!r.ok) throw new Error((await r.text())||r.statusText);
  return r.headers.get('content-type')?.includes('application/json') ? r.json() : r.text();
}

function t(key, vars={}) {
  let value = key.split('.').reduce((o, k) => o?.[k], translations) || key;
  Object.keys(vars).forEach(k => value = value.replace(`{{${k}}}`, vars[k]));
  return value;
}

async function loadConfig() {
  config = await api('/api/config');
  window.BOT_USERNAME = config.botUsername;
}

async function loadTranslations(lang) {
  currentLang = lang;
  translations = await api(`/api/translations/${lang}`);
  updatePageText();
}

function updatePageText() {
  const el = (sel, key, vars) => { const e = $(sel); if(e) e.textContent = t(key, vars); };
  const attr = (sel, attribute, key, vars) => { const e = $(sel); if(e) e.setAttribute(attribute, t(key, vars)); };
  
  el('#auth-screen h1', 'app.title');
  el('.tab[data-tab="telegram"]', 'auth.telegram_login');
  el('.tab[data-tab="login"]', 'auth.username_password');
  el('.tab[data-tab="signup"]', 'auth.signup');
  el('#telegram-tab h3', 'auth.telegram_login');
  el('#login-tab h3', 'auth.username_password');
  el('#signup-tab h3', 'auth.signup');
  el('#app-screen header h1', 'app.title');
  el('#logout-btn', 'app.logout');
  
  attr('#login-username', 'placeholder', 'auth.username');
  attr('#login-password', 'placeholder', 'auth.password');
  attr('#signup-username', 'placeholder', 'auth.username');
  attr('#signup-password', 'placeholder', 'auth.password_min');
  
  const loginBtn = $('#login-form button[type="submit"]');
  if(loginBtn) loginBtn.textContent = t('auth.login_button');
  
  const signupBtn = $('#signup-form button[type="submit"]');
  if(signupBtn) signupBtn.textContent = t('auth.signup_button');
  
  const panel = $('.card h2');
  if(panel) panel.textContent = `1) ${t('dashboard.country_service')}`;
  
  el('#refresh', 'ui.refresh');
  el('#buy', 'dashboard.contact_admin');
  el('#note', 'dashboard.codes_in_telegram');
}

function showAuth() {
  $('#auth-screen').style.display = 'flex';
  $('#app-screen').style.display = 'none';
}

function showApp() {
  $('#auth-screen').style.display = 'none';
  $('#app-screen').style.display = 'block';
}

async function loadMe() {
  try {
    const me = await api('/api/me');
    if (me.lang && me.lang !== currentLang) {
      await loadTranslations(me.lang);
    }
    $('#user-info').innerHTML = `Signed in as <code>${me.username||me.userId}</code> — Balance: <b>$${me.balance.toFixed(2)}</b>`;
    showApp();
    return me;
  } catch {
    showAuth();
    throw new Error('NO_AUTH');
  }
}

async function refreshPrice() {
  const country = $$('input[name=country]').find(x=>x.checked)?.value || 'EG';
  const p = await api(`/api/prices?country=${country}`);
  $('#pricebox').innerText = `${t('dashboard.price')}: $${(p.cost||0).toFixed(2)} | ${t('dashboard.available')}: ${p.available||0}`;
  return p;
}

async function renderActs() {
  const data = await api('/api/activations');
  const root = $('#acts');
  root.innerHTML = '';
  if (!data.activations.length) { root.innerHTML = `<div class="muted">No activations yet.</div>`; return; }
  for (const a of data.activations) {
    const tag = a.status==='ok' ? 'ok' : (a.status==='waiting'?'wait':'bad');
    const code = a.code ? `<code>${a.code}</code>` : `<span class="muted">(pending)</span>`;
    const el = document.createElement('div');
    el.className = 'item';
    el.innerHTML = `
      <div>Phone: <code>${a.phone}</code> — <span class="tag ${tag}">${a.status}</span></div>
      <div>Code: ${code}</div>
      <div>Price: $${(a.price||0).toFixed(2)} • ID: <code>${a.id}</code></div>
    `;
    root.appendChild(el);
    if (!a.code) pollCode(a.id, el);
  }
}

async function pollCode(id, itemEl) {
  for (let i=0;i<60;i++) {
    await sleep(5000);
    try {
      const st = await api(`/api/activation-status/${id}`);
      if (st.code) {
        itemEl.querySelector('.tag').className = 'tag ok';
        itemEl.querySelector('.tag').textContent = 'ok';
        const codeDiv = itemEl.querySelectorAll('div')[1];
        codeDiv.innerHTML = `Code: <code>${st.code}</code>`;
        break;
      }
    } catch {}
  }
}

async function buy() {
  try {
    const res = await api('/api/admins');
    const msgEl = $('#buy-msg');
    msgEl.innerHTML = '';
    
    res.admins.forEach((admin) => {
      const adminCard = document.createElement('div');
      adminCard.style.cssText = 'margin:10px 0;padding:15px;background:#1a1a2e;border-radius:8px;display:flex;justify-content:space-between;align-items:center';
      adminCard.innerHTML = `
        <div>
          <strong>@${admin.username}</strong>
          <div style="color:#888;font-size:0.9em">ID: ${admin.id}</div>
        </div>
        <a href="${admin.telegramLink}" target="_blank" style="padding:8px 16px;background:#0088cc;color:white;text-decoration:none;border-radius:5px;font-weight:500">
          💬 ${t('dashboard.chat_telegram')}
        </a>
      `;
      msgEl.appendChild(adminCard);
    });
  } catch (e) {
    $('#buy-msg').textContent = `Failed to load admin contacts: ${e.message||e}`;
  }
}

async function logout() {
  await api('/api/logout', { method:'POST' });
  showAuth();
}

window.onTelegramAuth = async function(user) {
  try {
    await api('/api/auth/telegram', { method:'POST', body: JSON.stringify(user) });
    await loadMe();
    await refreshPrice();
    await renderActs();
  } catch (e) {
    alert('Telegram auth failed: ' + e.message);
  }
};

$$('.tab').forEach(tab => {
  tab.onclick = () => {
    $$('.tab').forEach(t => t.classList.remove('active'));
    $$('.auth-tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    $(`#${tab.dataset.tab}-tab`).classList.add('active');
  };
});

$('#login-form').onsubmit = async (e) => {
  e.preventDefault();
  const username = $('#login-username').value;
  const password = $('#login-password').value;
  try {
    await api('/api/auth/login', { method:'POST', body: JSON.stringify({ username, password }) });
    await loadMe();
    await refreshPrice();
    await renderActs();
  } catch (e) {
    $('#login-error').textContent = 'Login failed: ' + e.message;
  }
};

$('#signup-form').onsubmit = async (e) => {
  e.preventDefault();
  const username = $('#signup-username').value;
  const password = $('#signup-password').value;
  try {
    await api('/api/auth/signup', { method:'POST', body: JSON.stringify({ username, password }) });
    await loadMe();
    await refreshPrice();
    await renderActs();
  } catch (e) {
    $('#signup-error').textContent = 'Signup failed: ' + e.message;
  }
};

function loadTelegramWidget() {
  const container = $('#telegram-login');
  container.innerHTML = '';
  const script = document.createElement('script');
  script.src = 'https://telegram.org/js/telegram-widget.js?22';
  script.async = true;
  script.setAttribute('data-telegram-login', window.BOT_USERNAME);
  script.setAttribute('data-size', 'large');
  script.setAttribute('data-auth-url', `${window.location.origin}/api/auth/telegram`);
  script.setAttribute('data-onauth', 'onTelegramAuth(user)');
  script.setAttribute('data-request-access', 'write');
  container.appendChild(script);
}

(async () => {
  await loadConfig();
  
  const storedLang = document.cookie.match(/i18next=(\w+)/)?.[1] || config.defaultLang || 'en';
  await loadTranslations(storedLang);
  
  $$('.lang-btn').forEach(btn => {
    btn.onclick = async () => {
      const lang = btn.dataset.lang;
      document.cookie = `i18next=${lang}; max-age=${365*24*60*60}; path=/`;
      await loadTranslations(lang);
    };
  });
  
  try { 
    await loadMe(); 
    await refreshPrice();
    await renderActs();
    
    $('#refresh').onclick = refreshPrice;
    $('#buy').onclick = buy;
    $('#logout-btn').onclick = logout;
  } catch { 
    loadTelegramWidget();
    return; 
  }
})();
