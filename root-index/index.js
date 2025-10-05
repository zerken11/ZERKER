const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

app.get("/", (_req, res) => {
  res.json({ status: "ok", message: "✅ Bot is running" });
});

app.get("/health", (_req, res) => {
  res.status(200).send("OK");
});

app.listen(PORT, () => {
  console.log(`✅ Bot is running on port ${PORT}`);
});

module.exports = app;
