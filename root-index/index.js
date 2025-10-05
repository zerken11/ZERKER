const express = require("express");

const app = express();
const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || "0.0.0.0";

const statusPayload = Object.freeze({ status: "ok", message: "✅ Bot is running" });

app.get(["/", "/status"], (_req, res) => {
  res.json(statusPayload);
});

const sendHealth = (_req, res) => {
  res.status(200).send("OK");
};

app.get("/health", sendHealth);
app.head("/health", sendHealth);

const server = app.listen(PORT, HOST, () => {
  console.log(`✅ Bot is running on http://${HOST}:${PORT}`);
});

module.exports = app;
module.exports.server = server;
