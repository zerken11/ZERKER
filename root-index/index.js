const http = require("http");

const PORT = Number(process.env.PORT) || 3000;

const server = http.createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET, HEAD");
    res.end();
    return;
  }

  if (req.url === "/health") {
    res.statusCode = 200;
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    if (req.method === "GET") {
      res.end("OK");
    } else {
      res.end();
    }
    return;
  }

  if (req.url === "/") {
    const payload = { status: "ok", message: "✅ Bot is running" };
    const body = JSON.stringify(payload);
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.setHeader("Content-Length", Buffer.byteLength(body));
    if (req.method === "GET") {
      res.end(body);
    } else {
      res.end();
    }
    return;
  }

  res.statusCode = 404;
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  if (req.method === "GET") {
    res.end("Not Found");
  } else {
    res.end();
  }
});

server.listen(PORT, () => {
  console.log(`✅ Bot is running on port ${PORT}`);
});

module.exports = server;
