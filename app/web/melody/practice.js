// Practice mode runtime (docs/specs/practice-mode.md): onnxruntime-web session pair with a KV cache,
// masked decoding from melody.js, and the browser IO the Dart ModelStore uses (fetch with progress,
// Cache Storage, sha256). Loaded on demand through window.epMelodyImport (index.html), so the app
// start does not pay for onnxruntime. melody.js and vendor/ are copied in by tools/sync_content.py and
// tools/melody-model/web/fetch_ort.py; the model bytes come from Dart, already sha256-checked.
import * as ort from "./vendor/ort.wasm.min.mjs";
import { decode, generate, makeVocab } from "./melody.js";

ort.env.wasm.wasmPaths = new URL("./vendor/", import.meta.url).href;
const CACHE = "ep-melody";
let model = null, V = null;
// Timings for docs/research/practice-mode-timing.md: read globalThis.epMelodyStats in the console.
const stats = (globalThis.epMelodyStats = { loadMs: null, gens: [] });

export async function fetchBytes(url, onProgress) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  if (!r.body) return new Uint8Array(await r.arrayBuffer());
  const reader = r.body.getReader(), parts = [];
  let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(value);
    got += value.length;
    onProgress(got);
  }
  const out = new Uint8Array(got);
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

export async function sha256(bytes) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Cache Storage keyed by a same-origin pseudo URL; null when there is no cache (private window, http).
const cacheUrl = (key) => new URL(`/__ep_cache__/${key}`, location.origin).href;
export async function cacheGet(key) {
  if (!globalThis.caches) return null;
  const r = await (await caches.open(CACHE)).match(cacheUrl(key));
  return r ? new Uint8Array(await r.arrayBuffer()) : null;
}
export async function cachePut(key, bytes) {
  if (!globalThis.caches) return;
  await (await caches.open(CACHE)).put(cacheUrl(key), new Response(bytes));
}
export async function cacheDelete(key) {
  if (globalThis.caches) await (await caches.open(CACHE)).delete(cacheUrl(key));
}

// Same session pair as tools/melody-model/web/index.html (OrtModel).
class OrtModel {
  ids(rows, t) { return new ort.Tensor("int64", BigInt64Array.from(rows.flat(2), BigInt), [rows.length, t, 4]); }
  async run(x) {
    const r = await this.dec.run({ x, past_k: this.pk, past_v: this.pv });
    this.pk = r.present_k; this.pv = r.present_v;
    return r.h;
  }
  async start(prefix, n) {
    const { layers, heads, d } = this.c;
    this.pk = this.pv = new ort.Tensor("float32", new Float32Array(0), [layers, n, heads, 0, d / heads]);
    return this.run(this.ids(Array.from({ length: n }, () => prefix), prefix.length));
  }
  async next(steps) { return this.run(this.ids(steps.map((s) => [s]), 1)); }
  async heads(h, kind, pitch, dur) {
    const t = (a) => new ort.Tensor("int64", BigInt64Array.from(a, BigInt), [a.length]);
    const r = await this.headsSession.run({ h, kind: t(kind), pitch: t(pitch), dur: t(dur) });
    return [r.kind_logits.data, r.pitch_logits.data, r.dur_logits.data, r.finger_logits.data];
  }
}

// decoder/heads: verified bytes; vocab: JSON text; config: {layers, heads, d}.
export async function load(decoder, heads, vocabText, configJson) {
  const t0 = performance.now();
  ort.env.wasm.numThreads = globalThis.crossOriginIsolated ? Math.min(4, navigator.hardwareConcurrency || 1) : 1;
  const opts = { executionProviders: ["wasm"], graphOptimizationLevel: "all" };
  const m = new OrtModel();
  [m.dec, m.headsSession] = await Promise.all([ort.InferenceSession.create(decoder, opts), ort.InferenceSession.create(heads, opts)]);
  m.c = JSON.parse(configJson);
  V = makeVocab(JSON.parse(vocabText));
  model = m;
  stats.loadMs = performance.now() - t0;
  stats.threads = ort.env.wasm.numThreads;
}

// gen: practice.json `gen` (spec + mask). Returns JSON [{time, key, bars}] of finished, decodable candidates, best first.
export async function generateJson(genJson, n, seed, temperature) {
  if (!model) throw new Error("model not loaded");
  const spec = JSON.parse(genJson);
  if (spec.course && !V.kind.includes(`COURSE_${spec.course}`)) spec.course = "none";
  const t0 = performance.now();
  const cands = await generate(V, model, spec, { n, seed, temperature });
  stats.gens.push({ n, ms: performance.now() - t0, done: cands.filter((c) => c.done).length });
  const out = [];
  for (const c of cands) {
    if (!c.done) continue;
    try { out.push(decode(V, c.steps)); } catch { /* the rubric would refuse it anyway */ }
  }
  return JSON.stringify(out);
}
