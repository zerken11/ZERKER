module.exports = {
  apps: [
    {
      name: "sms-activate",
      script: "index.js",
      cwd: __dirname + "/sms-activate",
      autorestart: true,
    },
    {
      name: "tech-god-bug",
      script: "main.js",
      cwd: __dirname + "/tech-god-bug",
      autorestart: true,
    },
    {
      name: "root-index",
      script: "index.js",
      cwd: __dirname + "/root-index",
      autorestart: true,
    },
  ],
};
