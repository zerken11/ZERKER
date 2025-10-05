require("dotenv").config();

const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const crypto = require("crypto");

const express = require("express");
const cookieParser = require("cookie-parser");
const session = require("express-session");
const SQLiteStore = require("connect-sqlite3")(session);
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
const i18next = require("i18next");
const i18nextMiddleware = require("i18next-http-middleware");
const i18nextFs = require("i18next-fs-backend");
const { Telegraf } = require("telegraf");

const db = require("./lib/db-sqlite");
const { SmsActivateClient } = require("./lib/smsactivate");
const {
  installSecurity,
  secureCookieOptions,
  requireSameOrigin,
} = require("./lib/security");
const {
  formatMoney,
  parseAmountToCents,
  addCreditCents,
  getCreditsCents,
  getUser,
  getUserByIdentifier,
  getUserByUsername,
  setPasswordHash,
  upsertUser,
  listUserActivations,
  getActivation,
  updateActivation,
  getPrices,
  updatePrice,
  getUserLang,
  setUserLang,
} = db;
const { mainMenu } = require("./lib/menu");
const { aiChat } = require("./lib/deepseek");

const PORT = Number(process.env.PORT || 3000);
const BOT_TOKEN =
  process.env.BOT_TOKEN ||
  process.env.TELEGRAM_BOT_TOKEN ||
  process.env.TELEGRAM_TOKEN ||
  "";
const BOT_USERNAME = process.env.BOT_USERNAME || "";
const SESSION_SECRET = process.env.SESSION_SECRET || process.env.JWT_SECRET || uuidv4();
const BASE_URL = process.env.BASE_URL || "";
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || "";
const ADMIN_IDS = (process.env.ADMINS || process.env.ADMIN_IDS || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const SMS_API_KEY =
  process.env.SMS_PROVIDER_API_KEY ||
  process.env.SMS_ACTIVATE_API_KEY ||
  process.env.API_KEY ||
  "";
const TEST_MODE = /^true$/i.test(process.env.TEST_MODE || "");
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY || "";
const SUPPORTED_LANGS = (process.env.SUPPORTED_LANGS || "en,ar")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
const DEFAULT_LANG = SUPPORTED_LANGS.includes(process.env.DEFAULT_LANG)
  ? process.env.DEFAULT_LANG
  : SUPPORTED_LANGS[0] || "en";

const COUNTRY_CODES = { EG: "24", CA: "2" };
const FALLBACK_ADMIN_USERNAMES = {
  "725797724": "mvx_vi",
  "8190845140": "WH0lSNEXT",
};

const smsClient = new SmsActivateClient(SMS_API_KEY, TEST_MODE, console);
const translationCache = new Map();

function isAdmin(id) {
  return ADMIN_IDS.includes(String(id));
}

async function establishSession(req, userId) {
  return new Promise((resolve, reject) => {
    req.session.regenerate((err) => {
      if (err) return reject(err);
      req.session.userId = String(userId);
      req.session.createdAt = Date.now();
      resolve();
    });
  });
}

function getSessionUserId(req) {
  return req.session?.userId ? String(req.session.userId) : null;
}

function toPublicUser(user) {
  if (!user) return null;
  const creditsCents = Number(user.credits_cents || user.creditsCents || 0);
  return {
    userId: String(user.id),
    username: user.username_local || user.username || null,
    firstName: user.first_name || user.firstName || null,
    lang: user.lang || DEFAULT_LANG,
    balance: Number(creditsCents) / 100,
    creditsCents,
    createdAt: user.createdAt || null,
  };
}

async function loadTranslations(lang) {
  const normalized = SUPPORTED_LANGS.includes(lang) ? lang : null;
  if (!normalized) return null;
  if (translationCache.has(normalized)) {
    return translationCache.get(normalized);
  }
  const file = path.join(
    __dirname,
    "locales",
    normalized,
    "common.json",
  );
  const data = JSON.parse(await fsp.readFile(file, "utf8"));
  translationCache.set(normalized, data);
  return data;
}

async function fetchPrice(country) {
  const countryCode = COUNTRY_CODES[country] || country;
  const service = "wa";
  let remoteCost = null;
  let remoteAvailable = null;
  if (SMS_API_KEY) {
    try {
      const remote = await smsClient.getPrices(service, countryCode);
      if (remote && typeof remote.cost === "number") {
        remoteCost = Number(remote.cost);
      }
      if (remote && remote.count !== undefined) {
        remoteAvailable = Number(remote.count);
      }
    } catch (err) {
      console.warn("⚠️  Failed to fetch remote prices:", err.message);
    }
  }

  const stored = getPrices();
  const storedCost = stored?.[country] ?? null;
  if (remoteCost != null) {
    updatePrice("whatsapp", country, remoteCost);
  }
  const cost = remoteCost != null ? remoteCost : storedCost;
  return {
    cost,
    available: remoteAvailable,
    currency: stored?.currency || "USD",
  };
}

function ensureDataDir() {
  const dir = path.join(__dirname, "data");
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

db.init();
ensureDataDir();

async function bootstrap() {
  await i18next
    .use(i18nextFs)
    .use(i18nextMiddleware.LanguageDetector)
    .init({
      fallbackLng: DEFAULT_LANG,
      preload: SUPPORTED_LANGS,
      backend: {
        loadPath: path.join(__dirname, "locales", "{{lng}}", "common.json"),
      },
      detection: {
        order: ["cookie", "querystring", "header"],
        caches: ["cookie"],
      },
      interpolation: { escapeValue: false },
    });

  const app = express();

  installSecurity(app, { baseUrl: BASE_URL, publicUrl: PUBLIC_BASE_URL });

  app.use(cookieParser());
  app.use(express.json({ limit: "1mb" }));
  app.use(express.urlencoded({ extended: false }));
  app.use(
    session({
      store: new SQLiteStore({
        dir: path.join(__dirname, "data"),
        db: "sessions.sqlite",
      }),
      secret: SESSION_SECRET,
      resave: false,
      saveUninitialized: false,
      cookie: secureCookieOptions(PUBLIC_BASE_URL || BASE_URL),
    }),
  );
  app.use(i18nextMiddleware.handle(i18next));
  app.use(requireSameOrigin(BASE_URL, PUBLIC_BASE_URL));
  app.use(
    express.static(path.join(__dirname, "public"), {
      maxAge: "1h",
      extensions: ["html"],
    }),
  );

  function requireAuth(req, res, next) {
    const uid = getSessionUserId(req);
    if (!uid) {
      return res.status(401).json({ error: "UNAUTHENTICATED" });
    }
    next();
  }

  app.get("/api/health", (req, res) => {
    res.json({ ok: true, time: new Date().toISOString() });
  });

  app.get("/api/config", (req, res) => {
    res.json({
      botUsername: BOT_USERNAME,
      testMode: TEST_MODE,
      supportedLanguages: SUPPORTED_LANGS,
    });
  });

  app.get("/api/translations/:lang", async (req, res) => {
    const lang = req.params.lang;
    try {
      const data = await loadTranslations(lang);
      if (!data) {
        return res.status(404).json({ error: "LANG_NOT_SUPPORTED" });
      }
      res.cookie("i18next", lang, {
        maxAge: 30 * 24 * 3600 * 1000,
        sameSite: "lax",
      });
      res.json(data);
    } catch (err) {
      console.error("Failed to load translations", err);
      res.status(500).json({ error: "TRANSLATION_LOAD_FAILED" });
    }
  });

  app.get("/api/me", requireAuth, (req, res) => {
    const uid = getSessionUserId(req);
    const user = getUser(uid);
    if (!user) {
      return res.status(404).json({ error: "USER_NOT_FOUND" });
    }
    res.json({ ok: true, user: toPublicUser(user) });
  });

  app.post("/api/logout", (req, res) => {
    if (!req.session) return res.json({ ok: true });
    req.session.destroy((err) => {
      if (err) {
        console.error("Failed to destroy session", err);
        return res.status(500).json({ error: "LOGOUT_FAILED" });
      }
      res.clearCookie("connect.sid");
      res.json({ ok: true });
    });
  });

  app.get("/api/prices", requireAuth, async (req, res) => {
    const country = (req.query.country || "EG").toString().toUpperCase();
    try {
      const price = await fetchPrice(country);
      res.json({ ok: true, ...price });
    } catch (err) {
      console.error("Failed to fetch prices", err);
      res.status(500).json({ error: "PRICE_FETCH_FAILED" });
    }
  });

  app.get("/api/activations", requireAuth, (req, res) => {
    const uid = getSessionUserId(req);
    const items = listUserActivations(uid, 25).map((act) => ({
      id: String(act.id),
      phone: act.phone || null,
      service: act.service || "wa",
      country: act.country || "EG",
      status: act.status || "waiting",
      price: Number(act.price || 0),
      code: act.code || null,
      createdAt: act.createdAt || null,
    }));
    res.json({ ok: true, activations: items });
  });

  app.get("/api/activation-status/:id", requireAuth, async (req, res) => {
    const uid = getSessionUserId(req);
    const id = req.params.id;
    let act = getActivation(id);
    if (!act || String(act.userId) !== String(uid)) {
      return res.status(404).json({ error: "NOT_FOUND" });
    }

    if (!act.code && SMS_API_KEY) {
      try {
        const status = await smsClient.getStatus(id);
        if (status && status.code) {
          updateActivation(id, { code: status.code, status: "ok" });
          act = getActivation(id);
        }
      } catch (err) {
        console.warn("⚠️  Failed to refresh activation status:", err.message);
      }
    }

    res.json({
      ok: true,
      status: act.status || "waiting",
      code: act.code || null,
      phone: act.phone || null,
    });
  });

  app.get("/api/admins", (req, res) => {
    const ids = ADMIN_IDS.length ? ADMIN_IDS : Object.keys(FALLBACK_ADMIN_USERNAMES);
    const admins = ids.map((id) => {
      const user = getUser(id);
      const username =
        user?.username ||
        user?.username_local ||
        FALLBACK_ADMIN_USERNAMES[id] ||
        null;
      const link = username
        ? `https://t.me/${username}`
        : `https://t.me/${id}`;
      return {
        id: String(id),
        username: username || String(id),
        telegramLink: link,
      };
    });
    res.json({ ok: true, admins });
  });

  function verifyTelegramAuth(data) {
    if (!BOT_TOKEN) throw new Error("BOT_TOKEN_NOT_CONFIGURED");
    const { hash, ...rest } = data || {};
    if (!hash) throw new Error("MISSING_HASH");
    const check = Object.keys(rest)
      .sort()
      .map((key) => `${key}=${rest[key]}`)
      .join("\n");
    const secret = crypto
      .createHash("sha256")
      .update(BOT_TOKEN)
      .digest();
    const hmac = crypto
      .createHmac("sha256", secret)
      .update(check)
      .digest("hex");
    if (hmac !== hash) throw new Error("INVALID_SIGNATURE");
    return rest;
  }

  app.post("/api/auth/telegram", async (req, res) => {
    try {
      const payload = verifyTelegramAuth(req.body);
      const userId = String(payload.id);
      const langCandidate = String(payload.language_code || "")
        .slice(0, 2)
        .toLowerCase();
      const lang = SUPPORTED_LANGS.includes(langCandidate)
        ? langCandidate
        : DEFAULT_LANG;
      upsertUser({
        id: userId,
        first_name: payload.first_name || null,
        username: payload.username || null,
        lang,
        balance: 0,
      });
      if (lang) setUserLang(userId, lang);
      await establishSession(req, userId);
      const user = getUser(userId);
      res.json({ ok: true, user: toPublicUser(user) });
    } catch (err) {
      console.error("Telegram auth failed", err);
      res.status(400).json({ error: "TELEGRAM_AUTH_FAILED" });
    }
  });

  const authSchema = {
    username: {
      validate(value) {
        const s = String(value || "").trim();
        if (s.length < 3 || s.length > 32) return false;
        return /^[a-zA-Z0-9_]+$/.test(s);
      },
    },
    password: {
      validate(value) {
        const s = String(value || "").trim();
        return s.length >= 6 && s.length <= 128;
      },
    },
  };

  app.post("/api/auth/signup", async (req, res) => {
    const { username, password } = req.body || {};
    if (!authSchema.username.validate(username) || !authSchema.password.validate(password)) {
      return res.status(400).json({ error: "INVALID_INPUT" });
    }
    const normalized = String(username).trim().toLowerCase();
    if (getUserByUsername(normalized)) {
      return res.status(409).json({ error: "USERNAME_EXISTS" });
    }
    const id = uuidv4();
    const hash = await bcrypt.hash(String(password).trim(), 10);
    upsertUser({ id, username_local: normalized, lang: DEFAULT_LANG });
    setPasswordHash(id, normalized, hash);
    await establishSession(req, id);
    const user = getUser(id);
    res.json({ ok: true, user: toPublicUser(user) });
  });

  app.post("/api/auth/login", async (req, res) => {
    const { username, password } = req.body || {};
    if (!authSchema.username.validate(username) || !authSchema.password.validate(password)) {
      return res.status(400).json({ error: "INVALID_INPUT" });
    }
    const normalized = String(username).trim().toLowerCase();
    const user = getUserByUsername(normalized);
    if (!user?.passHash) {
      return res.status(401).json({ error: "BAD_CREDENTIALS" });
    }
    const ok = await bcrypt.compare(String(password).trim(), user.passHash);
    if (!ok) {
      return res.status(401).json({ error: "BAD_CREDENTIALS" });
    }
    await establishSession(req, user.id);
    res.json({ ok: true, user: toPublicUser(user) });
  });

  app.post("/api/ai", requireAuth, async (req, res) => {
    if (!DEEPSEEK_API_KEY) {
      return res.status(503).json({ error: "AI_DISABLED" });
    }
    const prompt = String(req.body?.prompt || "").trim();
    if (!prompt) {
      return res.status(400).json({ error: "EMPTY_PROMPT" });
    }
    try {
      const reply = await aiChat(DEEPSEEK_API_KEY, prompt);
      res.json({ ok: true, reply });
    } catch (err) {
      console.error("DeepSeek request failed", err);
      res.status(502).json({ error: "AI_ERROR" });
    }
  });

  app.get("*", (req, res) => {
    res.sendFile(path.join(__dirname, "public", "index.html"));
  });

  const server = app.listen(PORT, () => {
    console.log(`✅ Server listening on port ${PORT}`);
  });

  setupBot();

  return server;
}

function setupBot() {
  if (!BOT_TOKEN) {
    console.warn("⚠️  BOT_TOKEN not set. Telegram bot disabled.");
    return;
  }
  const bot = new Telegraf(BOT_TOKEN);

  bot.start((ctx) => {
    const tgId = String(ctx.from.id);
    const langCandidate = (ctx.from.language_code || "").slice(0, 2).toLowerCase();
    const lang = SUPPORTED_LANGS.includes(langCandidate)
      ? langCandidate
      : DEFAULT_LANG;
    upsertUser({
      id: tgId,
      first_name: ctx.from.first_name || null,
      username: ctx.from.username || null,
      lang,
    });
    const t = i18next.getFixedT(lang);
    ctx.reply(t("bot.start"), { reply_markup: mainMenu() });
  });

  bot.command("help", (ctx) => {
    const lang = getUserLang(String(ctx.from.id)) || DEFAULT_LANG;
    const t = i18next.getFixedT(lang);
    ctx.reply(t("bot.help"));
  });

  bot.command("credit", (ctx) => {
    const tgId = String(ctx.from.id);
    const lang = getUserLang(tgId) || DEFAULT_LANG;
    const t = i18next.getFixedT(lang);
    const cents = getCreditsCents(tgId);
    ctx.reply(
      t("bot.credit", {
        amount: formatMoney(cents),
      }),
    );
  });

  bot.command("addcredit", (ctx) => {
    const tgId = String(ctx.from.id);
    const lang = getUserLang(tgId) || DEFAULT_LANG;
    const t = i18next.getFixedT(lang);
    if (!isAdmin(tgId)) {
      return ctx.reply(t("bot.not_admin"));
    }
    const args = ctx.message.text.split(/\s+/).slice(1);
    if (args.length < 2) {
      return ctx.reply("Usage: /addcredit <user> <amount>");
    }
    const identifier = args[0];
    const amountCents = parseAmountToCents(args[1]);
    if (amountCents == null) {
      return ctx.reply(t("bot.invalid_amount"));
    }
    const target = getUserByIdentifier(identifier);
    if (!target) {
      return ctx.reply(t("bot.user_not_found"));
    }
    const note = args.slice(2).join(" ") || null;
    const result = addCreditCents(target.id, amountCents, tgId, note);
    if (!result.ok) {
      return ctx.reply(`Error: ${result.error}`);
    }
    ctx.reply(
      t("bot.credit_added", {
        amount: formatMoney(amountCents),
        who: target.username_local || target.username || target.id,
        newAmount: formatMoney(result.newBal),
        currency: "USD",
      }),
    );
  });

  bot.command("prices", async (ctx) => {
    const tgId = String(ctx.from.id);
    const lang = getUserLang(tgId) || DEFAULT_LANG;
    const t = i18next.getFixedT(lang);
    const [eg, ca] = await Promise.all([fetchPrice("EG"), fetchPrice("CA")]);
    ctx.reply(
      t("bot.prices", {
        price_eg: eg.cost != null ? eg.cost.toFixed(2) : "-",
        count_eg: eg.available != null ? eg.available : "-",
        price_ca: ca.cost != null ? ca.cost.toFixed(2) : "-",
        count_ca: ca.available != null ? ca.available : "-",
      }),
    );
  });

  bot.launch()
    .then(() => console.log("🤖 Telegram bot started"))
    .catch((err) => console.error("Failed to launch bot", err));

  process.once("SIGINT", () => bot.stop("SIGINT"));
  process.once("SIGTERM", () => bot.stop("SIGTERM"));
}

bootstrap().catch((err) => {
  console.error("Fatal error during bootstrap", err);
  process.exit(1);
});
