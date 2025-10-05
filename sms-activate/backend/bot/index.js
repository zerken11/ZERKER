require('dotenv').config();
const { Telegraf } = require('telegraf');
const registerAdminHandlers = require('./admin');

const token = process.env.TELEGRAM_BOT_TOKEN;

if (!token) {
  console.error('Missing TELEGRAM_BOT_TOKEN');
  process.exit(1);
}

const ADMIN_IDS = (process.env.ADMIN_IDS || '')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);

const bot = new Telegraf(token);

bot.start((ctx) => ctx.reply('🤖 Ready. Use /addcredit <email> <amount> (admins only) or /balance <email>'));
registerAdminHandlers(bot, { adminIds: ADMIN_IDS });

bot.launch().then(() => console.log('Bot up.'));

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
