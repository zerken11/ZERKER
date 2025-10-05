const axios = require("axios");
axios.defaults.timeout = 12000;
axios.defaults.maxRedirects = 0;

const API = "https://api.sms-activate.ae/stubs/handler_api.php";
const ALLOWED_HOST = "api.sms-activate.ae";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function assertAllowed(url) {
  try {
    const { hostname } = new URL(url);
    if (hostname !== ALLOWED_HOST) throw new Error(`Bad host: ${hostname}`);
  } catch (e) {
    throw new Error("Invalid URL");
  }
}

function parseLegacyKV(text) {
  if (typeof text !== "string") return null;
  const p = text.split(":");
  if (p[0] === "ACCESS_NUMBER" && p.length >= 3)
    return { id: p[1], phone: p[2] };
  if (p[0] === "STATUS_OK") return { code: p.slice(1).join(":").trim() };
  return null;
}

class SmsActivateClient {
  constructor(apiKey, testMode = false, log = console) {
    this.apiKey = apiKey;
    this.testMode = testMode;
    this.log = log;
  }

  async getCountries() {
    if (this.testMode)
      return {
        Egypt: { id: 24, eng: "Egypt" },
        Canada: { id: 2, eng: "Canada" },
      };
    const url = `${API}?api_key=${this.apiKey}&action=getCountries`;
    assertAllowed(url);
    const { data } = await axios.get(url);
    return data;
  }

  async getPrices(service, country) {
    if (this.testMode) return { cost: 0.15, count: 99 };
    const url = `${API}?api_key=${this.apiKey}&action=getPrices&service=${service}&country=${country}`;
    assertAllowed(url);
    const { data } = await axios.get(url);
    const key = String(country);
    const svc = data?.[key]?.[service];
    if (!svc) return { cost: null, count: 0 };
    return {
      cost: parseFloat(svc.cost),
      count: parseInt(svc.count || "0", 10),
    };
  }

  async getNumber(service, country) {
    if (this.testMode)
      return {
        id: String(Math.floor(Math.random() * 1e9)),
        phone: "+20-123-456-7890",
      };
    const url = `${API}?api_key=${this.apiKey}&action=getNumber&service=${service}&country=${country}`;
    assertAllowed(url);
    const { data } = await axios.get(url, { responseType: "text" });
    if (typeof data === "string") {
      const kv = parseLegacyKV(data);
      if (kv) return kv;
    }
    if (data && data.activationId && data.phoneNumber)
      return { id: String(data.activationId), phone: data.phoneNumber };
    throw new Error(`getNumber unexpected: ${JSON.stringify(data)}`);
  }

  async setStatus(id, status) {
    if (this.testMode) return { ok: true, status };
    const url = `${API}?api_key=${this.apiKey}&action=setStatus&status=${status}&id=${id}`;
    assertAllowed(url);
    const { data } = await axios.get(url, { responseType: "text" });
    return { data };
  }

  async getStatus(id) {
    if (this.testMode) return { code: "123-456" };
    const url = `${API}?api_key=${this.apiKey}&action=getStatus&id=${id}`;
    assertAllowed(url);
    const { data } = await axios.get(url, { responseType: "text" });
    if (typeof data === "string") {
      const kv = parseLegacyKV(data);
      if (kv && kv.code) return kv;
      return { raw: data };
    }
    return data;
  }

  async waitForCode(id, { timeoutMs = 180000, pollMs = 5000 } = {}) {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      const s = await this.getStatus(id);
      if (s?.code) return { ok: true, code: s.code };
      await sleep(pollMs);
    }
    return { ok: false, timeout: true };
  }
}
module.exports = { SmsActivateClient };
