# Overview

This is a Node.js Telegram bot with web dashboard for SMS-Activate service. It provides temporary phone numbers for WhatsApp verification from Egypt and Canada. The system includes:

- **Triple Authentication**: Telegram Login Widget, Username/Password, OR Magic Link with JWT sessions
- **Credits System**: Integer-based credits (credits_cents) with full audit trail
- **Arabic/English Support**: Full bilingual interface with language toggle in bot and dashboard
- **SQLite Database**: Production-ready database with automatic JSON migration
- **TEST_MODE**: Zero-cost testing with fake numbers and codes
- **Web Dashboard**: Responsive HTML/CSS/JS with i18n support
- **Telegraf Bot**: Modern bot framework with inline keyboards and callbacks
- **DeepSeek AI**: Admin-only AI chat for assistance
- **Single Process**: Bot and web server run together for simplicity

# User Preferences

Preferred communication style: Simple, everyday language.

# System Architecture

## Frontend
- **Static Dashboard**: Vanilla JavaScript, no build step
- **Real-time Updates**: Auto-polling for SMS codes
- **Dark Theme**: Modern, clean UI
- **i18next**: Client-side internationalization with language detection

## Backend
- **Express.js**: Serves both API and static files
- **Telegraf Bot**: Modern framework with scene management and middleware
- **SQLite Database**: Better-sqlite3 for synchronous operations (data/app.db)
  - `users`: User accounts with credits_cents (integer-based balance)
  - `activations`: Phone number purchase history
  - `tokens`: Magic link authentication tokens
  - `prices`: WhatsApp pricing for EG/CA
  - `credit_tx`: Complete audit trail of all credit transactions
- **i18next**: Server-side internationalization with fs-backend
- **Port 5000**: Single server for bot + web

## Authentication & Authorization
- **Dual Auth System**: Three authentication methods:
  1. **Telegram Login Widget**: Official Telegram authentication with HMAC-SHA256 verification
  2. **Username/Password**: Local account signup/login with bcrypt password hashing
  3. **Magic Link** (legacy): Bot sends unique token → user clicks → auto-login to dashboard
- **JWT Sessions**: Secure token-based authentication with 7-day expiration
- **Password Security**: Bcrypt hashing with salt rounds = 10
- **Admin Authorization**: Up to 2 admin IDs (comma-separated in ADMINS secret)
- **String ID Handling**: All user IDs normalized to strings for consistency

## Credits System
- **Integer-Based**: credits_cents field avoids floating-point precision issues
- **Audit Trail**: credit_tx table records every transaction with timestamp, admin, and user
- **Bot Commands**:
  - `/credit` - Check your current balance
  - `/addcredit @username 10.50` - Admin-only: Add credits to user (by username or ID)
- **Helper Functions**:
  - `getCreditsCents(tgId)` - Get user's balance in cents
  - `addCreditCents(tgId, deltaCents, adminId, note)` - Add/deduct with audit
  - `formatMoney(cents)` - Convert cents to dollars (e.g., 1050 → "10.50")
  - `parseAmountToCents(str)` - Convert dollar string to cents (e.g., "10.50" → 1050)
  - `getUserByIdentifier(x)` - Find user by @username or numeric ID

## External Services
- **SMS-Activate API**: Handler API endpoints at api.sms-activate.ae
  - getCountries, getPrices, getNumber, getStatus
  - Only Egypt & Canada for WhatsApp service
- **DeepSeek AI**: POST https://api.deepseek.com/chat/completions
  - Admin command: /ai <question>

## Testing & Development
- **TEST_MODE**: Set to "true" for fake numbers/codes
  - Simulates full purchase flow
  - No API charges
  - Returns fake code: 123-456

## Environment Variables
- **BOT_TOKEN**: Telegram bot authentication token
- **SESSION_SECRET**: JWT signing secret (used for JWT_SECRET)
- **ADMINS**: Comma-separated admin chat IDs (max 2: 725797724, 8190845140)
- **SMS_PROVIDER_API_KEY**: SMS-Activate API key
- **DEEPSEEK_API_KEY**: Optional AI service key
- **BASE_URL**: Your Replit URL for magic links
- **PUBLIC_BASE_URL**: Custom domain URL (e.g., https://www.fakew.cyou)
- **TEST_MODE**: Set "true" for zero-cost testing

## Configuration
- **BOT_USERNAME**: Configured as @Fake_WA_bot for Telegram Login Widget

# External Dependencies

## Services
- Telegram Bot API
- SMS-Activate API (Egypt & Canada only, WhatsApp only)
- DeepSeek API (optional, admin-only)

## NPM Packages
- express: Web server
- telegraf: Modern Telegram bot framework
- better-sqlite3: Fast synchronous SQLite database
- i18next: Internationalization framework
- i18next-fs-backend: File system backend for i18next
- i18next-http-middleware: HTTP middleware for i18next
- axios: HTTP client
- cookie-parser: Session management
- express-session: Session middleware
- connect-sqlite3: SQLite session store
- csurf: CSRF protection middleware
- zod: Schema validation library
- dotenv: Environment variables
- uuid: Token generation
- bcryptjs: Password hashing
- jsonwebtoken: JWT session tokens
- helmet: Security headers (CSP, HSTS, etc.)
- cors: Cross-origin resource sharing
- hpp: HTTP parameter pollution protection
- compression: Response compression
- express-rate-limit: Rate limiting middleware
- express-slow-down: Request slowdown middleware
- dayjs: Modern date library for timestamps
- ejs: Template engine (for future use)
- ejs-locals: EJS layout support (for future use)

# Recent Changes (Oct 1, 2025)

## Latest Update - Credits System Integration
- ✅ **Integer-Based Credits**: Added credits_cents column to users table
  - Avoids floating-point precision issues
  - Stored as cents (e.g., $10.50 = 1050 cents)
  
- ✅ **Credit Audit Trail**: New credit_tx table
  - Records every credit transaction
  - Tracks admin_tg_id, user_tg_id, delta_cents, timestamp, and note
  - Full accountability for all balance changes

- ✅ **Bot Commands**:
  - `/credit` - Shows user's current balance in USD
  - `/addcredit @username 10.50` - Admin-only command to add credits
  - Supports both @username and numeric Telegram ID
  - Bilingual responses (Arabic/English) based on user preference

- ✅ **Helper Functions**: Added to lib/db-sqlite.js
  - `formatMoney(cents)` - Convert cents to formatted dollars
  - `parseAmountToCents(str)` - Parse dollar string to cents
  - `getUserByIdentifier(x)` - Find user by username or ID
  - `addCreditCents()` - Add/deduct with validation and audit
  - `getCreditsCents()` - Get user's balance

- ✅ **Admin Usernames**: Contact display now shows @mvx_vi and @WH0lSNEXT
  - Updated /api/admins endpoint with proper usernames
  - Telegram deep links: https://t.me/mvx_vi and https://t.me/WH0lSNEXT

## Previous Update - Dashboard i18n Integration & Telegram Widget Fix
- ✅ **Dashboard Internationalization**: Full client-side Arabic/English translation support
  - Added /api/config endpoint to provide BOT_USERNAME for Telegram widget
  - Added /api/translations/:lang endpoint for loading translation files
  - Implemented client-side translation engine with t() function
  - Dynamic page text updates when language is changed
  - Translations loaded from server-side i18next locales
  - Auto-detection of user's language preference from cookies
  
- ✅ **Telegram Login Widget Fixed**: BOT_USERNAME now properly injected
  - Widget receives @Fake_WA_bot username from config API
  - Proper async loading of config before widget initialization
  - Fixed translation key selectors for form inputs and buttons

## Previous Update - Enhanced Security & Data Layer
- ✅ **Cherry-Picked Security Enhancements**: Added production-grade security features
  - CSRF protection with csurf middleware (cookie-based tokens)
  - SQLite session store with connect-sqlite3 (data/sessions.db)
  - Zod schema validation for all API inputs
  - Input sanitization and type safety on auth endpoints
  - Enhanced error handling with validation details

- ✅ **Prices Database Table**: WhatsApp pricing stored in SQLite
  - Real pricing data: Egypt ($0.16), Canada ($0.20)
  - Service-country unique constraints
  - Active/inactive flag for price management
  - Helper functions: getPrices(), updatePrice()

## Previous Update - Telegraf & SQLite Migration
- ✅ **Migrated to Telegraf Framework**: Upgraded from node-telegram-bot-api to Telegraf
  - Modern bot architecture with middleware and scenes
  - Better error handling and context management
  - Cleaner inline keyboard implementation
  - Improved callback query handling

- ✅ **Migrated to SQLite Database**: Production-ready database with automatic migration
  - Fast synchronous operations with better-sqlite3
  - Automatic JSON to SQLite migration (preserves data in backup)
  - Schema: users, activations, tokens, prices tables
  - Better query performance and data integrity
  - Language preference stored per user

- ✅ **Arabic/English Language Support**: Full bilingual interface
  - i18next internationalization framework
  - Bot language toggle with inline buttons
  - Dashboard language switcher in header (🇪🇬 AR / 🇬🇧 EN)
  - User preference persisted in database
  - Complete translations for all bot commands and UI elements

## Previous Updates (Earlier Oct 1, 2025)
- ✅ **Bot Username Configured**: @Fake_WA_bot now set in Telegram Login Widget
- ✅ **All Systems Tested**: 14/14 security and functionality tests passing

- ✅ **Security Hardening Complete**: Production-grade security implemented
  - Helmet.js with strict CSP (allows Telegram Login Widget)
  - Rate limiting (100 req/15min on auth, 300 req/min on API)
  - Slowdown protection on auth endpoints
  - CORS restricted to BASE_URL only
  - Same-origin enforcement on state-changing requests
  - Secure cookies (httpOnly, SameSite, secure flag for HTTPS)
  - Axios timeout (12s), no redirects, host validation (api.sms-activate.ae only)
  - HTTP parameter pollution protection
  - Response compression enabled
  - X-Powered-By disabled

- ✅ **Enhanced Authentication System**: Added dual auth support
  - Telegram Login Widget with HMAC verification
  - Username/Password signup and login with bcrypt
  - JWT-based session management (7-day tokens)
  - Database updates: getUserByUsername, setPasswordHash functions
  - Auth screen UI with tabbed interface (3 auth methods)

- Migrated from Python to Node.js for better web dashboard integration
- Added magic link authentication system (now legacy support)
- Implemented TEST_MODE for cost-free end-to-end testing
- Created static web dashboard with dark theme
- Single-process deployment (bot + web server together)
