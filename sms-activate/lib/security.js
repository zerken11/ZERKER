const helmet = require('helmet');
const cors = require('cors');
const hpp = require('hpp');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const slowDown = require('express-slow-down');

function secureCookieOptions(baseUrl) {
  const isHttps = typeof baseUrl === 'string' && baseUrl.startsWith('https://');
  return { httpOnly: true, sameSite: 'lax', secure: !!isHttps, maxAge: 7 * 24 * 3600 * 1000 };
}

function requireSameOrigin(baseUrl, publicUrl) {
  const allowed = (v='') => {
    if (!baseUrl && !publicUrl) return true;
    if (!v) return false;
    if (baseUrl && v.startsWith(baseUrl)) return true;
    if (publicUrl && v.startsWith(publicUrl)) return true;
    return false;
  };
  return (req, res, next) => {
    if (!['POST','PUT','PATCH','DELETE'].includes(req.method)) return next();
    const origin = req.get('origin') || '';
    const referer = req.get('referer') || '';
    if ((origin && !allowed(origin)) || (referer && !allowed(referer))) {
      return res.status(403).json({ error: 'BAD_ORIGIN' });
    }
    next();
  };
}

function installSecurity(app, { baseUrl, publicUrl }) {
  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  app.use(helmet({
    contentSecurityPolicy: {
      useDefaults: true,
      directives: {
        "default-src": ["'self'"],
        "script-src": ["'self'", "https://telegram.org", "https://oauth.telegram.org", "'unsafe-inline'"],
        "connect-src": ["'self'"],
        "img-src": ["'self'", "data:", "https://telegram.org", "https://*.t.me", "https://oauth.telegram.org"],
        "frame-src": ["'self'", "https://oauth.telegram.org"],
        "style-src": ["'self'", "'unsafe-inline'"],
        "object-src": ["'none'"],
        "upgrade-insecure-requests": []
      }
    },
    referrerPolicy: { policy: "same-origin" },
    hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
    crossOriginOpenerPolicy: { policy: "same-origin-allow-popups" },
    crossOriginEmbedderPolicy: false
  }));

  app.use(hpp());
  app.use(compression());
  app.use((req, res, next) => {
    req.setTimeout?.(30_000);
    next();
  });

  const allowedOrigins = [baseUrl, publicUrl].filter(Boolean);
  if (allowedOrigins.length > 0) {
    app.use(cors({ origin: allowedOrigins, credentials: true }));
  } else {
    app.use(cors({ origin: false, credentials: true }));
  }

  const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 100, standardHeaders: true, legacyHeaders: false });
  const authSlow = slowDown({ windowMs: 15 * 60 * 1000, delayAfter: 20, delayMs: () => 250 });
  app.use(['/auth', '/auth/*', '/api/auth/*'], authSlow, authLimiter);

  const apiLimiter = rateLimit({ windowMs: 60 * 1000, max: 300, standardHeaders: true, legacyHeaders: false });
  app.use(['/api', '/api/*'], apiLimiter);
}

module.exports = { installSecurity, requireSameOrigin, secureCookieOptions };
