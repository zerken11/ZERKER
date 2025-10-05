const db = require('../db');

function isAdmin(telegramId, adminIds) {
  return adminIds.includes(String(telegramId));
}

function getUserByEmail(email) {
  return db.prepare('SELECT * FROM users WHERE email = ?').get(email.toLowerCase());
}

module.exports = function registerAdminHandlers(bot, { adminIds = [] } = {}) {
  bot.hears(/^\/addcredit\s+(\S+)\s+(-?\d+)$/i, (ctx) => {
    if (!isAdmin(ctx.from.id, adminIds)) {
      return ctx.reply('❌ Admin only.');
    }

    const email = ctx.match[1];
    const amount = parseInt(ctx.match[2], 10);
    const user = getUserByEmail(email);

    if (!user) {
      return ctx.reply('❌ user not found');
    }

    db.prepare('INSERT OR IGNORE INTO credits (user_id, balance) VALUES (?, 0)').run(user.id);
    db.prepare(
      'UPDATE credits SET balance = balance + ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?'
    ).run(amount, user.id);

    const balance = db.prepare('SELECT balance FROM credits WHERE user_id = ?').get(user.id)?.balance ?? 0;
    return ctx.reply(`✅ ${email} new balance: ${balance}`);
  });

  bot.hears(/^\/balance(?:\s+(\S+))?$/i, (ctx) => {
    const email = ctx.match[1];
    if (email) {
      if (!isAdmin(ctx.from.id, adminIds)) {
        return ctx.reply('❌ Admin only for querying others.');
      }

      const user = getUserByEmail(email);
      if (!user) {
        return ctx.reply('❌ user not found');
      }

      const balance =
        db.prepare('SELECT balance FROM credits WHERE user_id = ?').get(user.id)?.balance ?? 0;
      return ctx.reply(`💳 ${email} balance: ${balance}`);
    }

    return ctx.reply('ℹ️ Provide email: /balance user@example.com');
  });
};
