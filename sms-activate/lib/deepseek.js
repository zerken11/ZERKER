const axios = require('axios');
async function aiChat(apiKey, prompt) {
  if (!apiKey) throw new Error('DEEPSEEK_API_KEY not set');
  const url = 'https://api.deepseek.com/chat/completions';
  const { data } = await axios.post(url, {
    model: 'deepseek-chat',
    messages: [
      { role: 'system', content: 'You are a terse assistant for a Telegram bot admin.' },
      { role: 'user', content: prompt }
    ]
  }, { headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' } });
  return data?.choices?.[0]?.message?.content?.trim() || '(no output)';
}
module.exports = { aiChat };
