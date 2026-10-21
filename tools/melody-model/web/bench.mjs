// Timing matrix for docs/research/melody-browser.md, run in desktop Chrome over the DevTools protocol.
//   python tools/melody-model/web/serve.py      (other terminal)
//   node tools/melody-model/web/bench.mjs [chrome.exe] > bench.jsonl   (one JSON line per configuration, then a summary)
// Each configuration gets a fresh page load (cold = first generate after load, warm = median of 5 more).
// Chrome runs with a throwaway profile and a visible window (background tabs are throttled).
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CHROME = process.argv[2] || "C:/Program Files/Google/Chrome/Application/chrome.exe";
const PAGE = "http://localhost:8780/";
const PORT = 9333;
const CONFIGS = [
  { backend: "wasm", variant: ".int8", threads: 1 },
  { backend: "wasm", variant: ".int8", threads: 4 },
  { backend: "wasm", variant: "", threads: 4 },
  { backend: "webgpu", variant: "", threads: 4 },
  { backend: "webgpu", variant: ".int8", threads: 4 },
];

const chrome = spawn(CHROME, [`--remote-debugging-port=${PORT}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), "melody-bench-"))}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1200,900", "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function page() {
  for (let i = 0; i < 50; i++) {
    try {
      const tabs = await fetch(`http://127.0.0.1:${PORT}/json`).then((r) => r.json());
      const t = tabs.find((x) => x.type === "page");
      if (t) return t.webSocketDebuggerUrl;
    } catch { /* not up yet */ }
    await sleep(200);
  }
  throw new Error("chrome did not start");
}

function cdp(url) {
  const ws = new WebSocket(url);
  let id = 0;
  const waits = new Map();
  ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && waits.has(m.id)) { waits.get(m.id)(m); waits.delete(m.id); } };
  const send = (method, params = {}) => new Promise((res) => { const i = ++id; waits.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
  return new Promise((res) => { ws.onopen = () => res({ send, close: () => ws.close() }); });
}

async function evaluate(c, expr) {
  const r = await c.send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true, timeout: 600000 });
  if (r.error) throw new Error(JSON.stringify(r.error));
  if (r.result.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails).slice(0, 500));
  return r.result.result.value;
}

const c = await cdp(await page());
const out = { chrome: null, results: [] };
for (const cfg of CONFIGS) {
  await c.send("Page.navigate", { url: `${PAGE}?backend=${cfg.backend}&r=${Math.random()}` });
  await sleep(1500);
  out.chrome ??= await evaluate(c, "navigator.userAgent.match(/Chrome\\/[\\d.]+/)[0]");
  let res;
  try {
  res = await evaluate(c, `(async () => {
    const $ = (id) => document.getElementById(id);
    $("lo").value = "C4"; $("hi").value = "C5"; $("variant").value = ${JSON.stringify(cfg.variant)}; $("threads").value = ${cfg.threads};
    await window.loadModel();
    const parity = await window.checkParity();
    const one = (o) => window.bench(o).then(({ spec, ...r }) => r);
    return { load: { ms: loadStats.ms, backend: loadStats.backend, variant: loadStats.variant, iso: crossOriginIsolated }, parity,
      batched8: await one({ runs: 5, n: 8, mode: "batched" }), sequential8: await one({ runs: 5, n: 8, mode: "sequential" }),
      single: await one({ runs: 5, n: 1, mode: "batched" }) };
  })()`);
  } catch (e) {
    out.results.push({ requested: cfg, error: e.message });
    console.error(cfg, "FAILED", e.message);
    continue;
  }
  out.results.push({ requested: cfg, ...res });
  console.error(cfg, res.load.backend, res.batched8.median_ms, res.sequential8.median_ms);
  console.log(JSON.stringify({ requested: cfg, ...res })); // one line per configuration
}
console.log(JSON.stringify({ chrome: out.chrome, failed: out.results.filter((r) => r.error) }));
c.close();
chrome.kill();
process.exit(0);
