function mainMenu() {
  return {
    inline_keyboard: [
      [
        {
          text: "🌐 Open Dashboard",
          url: process.env.BASE_URL || "https://example.com",
        },
      ],
      [{ text: "🇪🇬 Buy WhatsApp (Egypt)", callback_data: "BUY_WA_EG" }],
      [{ text: "🇨🇦 Buy WhatsApp (Canada)", callback_data: "BUY_WA_CA" }],
      [
        { text: "💳 Balance", callback_data: "BALANCE" },
        { text: "❓ Help", callback_data: "HELP" },
      ],
    ],
  };
}
function adminMenu() {
  return {
    inline_keyboard: [
      [
        { text: "➕ Add Credit", callback_data: "ADMIN_ADD_CREDIT" },
        { text: "👥 Users", callback_data: "ADMIN_LIST_USERS" },
      ],
      [{ text: "🤖 AI (DeepSeek)", callback_data: "ADMIN_AI" }],
    ],
  };
}
function buyConfirmMenu(priceLabel) {
  return {
    inline_keyboard: [
      [
        {
          text: `✅ Confirm Purchase (${priceLabel})`,
          callback_data: "BUY_CONFIRM",
        },
      ],
      [{ text: "↩️ Back", callback_data: "BACK_HOME" }],
    ],
  };
}
function pendingMenu(actId) {
  return {
    inline_keyboard: [
      [{ text: "🔁 Request Another SMS", callback_data: `ACT_RETRY:${actId}` }],
      [{ text: "🛑 Cancel", callback_data: `ACT_CANCEL:${actId}` }],
    ],
  };
}
module.exports = { mainMenu, adminMenu, buyConfirmMenu, pendingMenu };
