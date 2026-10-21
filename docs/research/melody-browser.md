# Melody model in the browser

Checked: 2026-10-20, rerun 2026-10-21. Sources: own measurements (below), onnxruntime-web 1.30.0 (npm, vendored by `web/fetch_ort.py`), onnxruntime 1.30.0 (Python: quantization and parity), torch 2.11 legacy ONNX exporter.

Question: can the step-4 melody model (11.09M params, D20) run in a browser tab fast enough to generate practice tunes on demand, and at what download cost?

Scope of every timing below: **desktop Chrome 155 on this machine** (Windows 11, 32 logical cores), page served by `web/serve.py` on localhost. Nothing here is measured on mobile.

## Setup

| Item | Value |
|---|---|
| Server | `python tools/melody-model/web/serve.py`: COOP `same-origin` + COEP `require-corp`, so `crossOriginIsolated` = true; `Cache-Control: no-store`; no compression |
| Runtime | onnxruntime-web 1.30.0 from `web/vendor/` (`ort.wasm.min.mjs`, `ort-wasm-simd-threaded.{mjs,wasm}`, sha256-pinned), `wasmPaths` = `vendor/`, wasm EP, graph optimization `all` |
| Integrity | every model file is fetched, hashed with `crypto.subtle.digest` and compared with `meta.json` before `InferenceSession.create` |
| Spec | 4/4, C, 8 bars, RH, range C4–C5, durations 2 and 4 |
| Decoding | masked (`web/melody.js`), temperature 1.0, KV cache, heads called once per field that has a real choice |

Threads: `numThreads > 1` only works when the page is cross-origin isolated (COOP/COEP). Without `serve.py`'s headers (e.g. `python -m http.server`) onnxruntime-web falls back to one thread, and the 4-thread rows do not apply.

Method: `window.loadModel()` timed with `performance.now()` from the click to both sessions ready (fetch, sha256, session create). Bytes from `performance.getEntriesByType("resource")`. `window.bench({runs: 5, n})`: one warm-up, then 5 generations with seeds 1–5; median. Tune length varies with the sample (64–105 decode steps after the spec prefix).

## Results

Final checkpoint `base1` (step 20,000, val loss 0.875), 2026-10-21, vendored runtime:

| Variant | Threads | Load | n = 1: ms per tune | n = 8: ms per batch | n = 8: ms per tune |
|---|---|---|---|---|---|
| int8 | 1 | 527 ms | 266 | 1,313 | 164 |
| int8 | 4 | 270 ms | 188 | 1,045 | 131 |

Earlier runs (2026-10-20, runtime from the jsdelivr CDN, `smoke3` weights, identical graph): int8 1 thread 419 / 2,528 ms, int8 4 threads 333 / 2,032 ms, fp32 1 thread 574 / 2,037 ms (n = 1 / n = 8). The spread between days is run-to-run variance (tab focus, other load), so treat ~0.2–0.4 s per tune and ~1–2.5 s per batch of 8 as the range.

| Download | Bytes |
|---|---|
| `decoder.int8.onnx` + `heads.int8.onnx` | 12.48 MB (fp32: 44.72 MB) |
| `ort-wasm-simd-threaded.wasm` | 14.24 MB uncompressed (3.07 MB brotli from the CDN) |
| runtime JS | 0.08 MB |

### Parity and quantization loss

Teacher-forced, KV-cache path vs PyTorch full sequence:

| Check | Runtime | Max abs logit diff | Max prob diff | Top-1 agreement |
|---|---|---|---|---|
| base1 final, Ode to Joy, fp32 | onnxruntime 1.30 CPU (Python) | 1.5e-5 | 1.5e-6 | 100% |
| base1 final, Ode to Joy, int8 | onnxruntime 1.30 CPU (Python) | 1.15 | **0.082** | 100% |
| base1 final, Ode to Joy, fp32 | onnxruntime-web 1.30 wasm (Chrome) | 6.0e-5 | 1.9e-5 | 100% |
| base1 final, Ode to Joy, int8 | onnxruntime-web 1.30 wasm (Chrome) | 0.49 | 0.058 | 99.5% |

The int8 max probability difference on the real checkpoint (0.082) is **above** the 0.05 bound the unit test uses on its toy 2-layer model. Max prob diff is a worst case over ~190 positions × 4 fields, so it does not by itself say whether quality drops. The measure that does is validation NLL (same loss as training, positions after `SPEC_END`):

| Validation NLL, 200 held-out tunes, 52,056 steps | total | kind | pitch | dur |
|---|---|---|---|---|
| PyTorch | 0.84643 | 0.27228 | 0.40352 | 0.17060 |
| ONNX fp32 | 0.84643 | 0.27228 | 0.40352 | 0.17060 |
| ONNX int8 | 0.84745 | 0.27238 | 0.40417 | 0.17088 |

int8 costs +0.0010 nats per step (+0.12%), mostly in pitch. That is small next to the training curve (val loss moved 0.98 → 0.875 over the last 12k steps), but it is a measured loss, not zero. Acceptance for a shipped checkpoint: int8 val NLL within 1% of fp32.

## Findings

- An 8-bar tune takes ~0.2–0.4 s; a batch of 8 candidates ~1–2.5 s on this desktop. Usable for "generate on node open" behind a short spinner, or in the background.
- fp32 and int8 run at about the same speed, and 4 threads help 20–30%: time is dominated by per-call overhead (one decoder call plus up to four heads calls per step, ~100 steps), not by matmuls.
- int8 cuts the model download 3.5x (44.7 → 12.5 MB) for +0.12% validation NLL.
- Vendoring the runtime means serving the 14 MB wasm ourselves; it needs brotli/gzip (3 MB) wherever it is hosted.

## Implications

- Ship int8, gated on the NLL check that `export.py` writes to `meta.json`.
- The model is 12.5 MB + 3 MB compressed wasm: a lazily downloaded, cached asset, not part of the first-load bundle.
- Distribution: the user approved GitHub Releases for weights (not git). Release asset downloads do not send CORS headers, so the page cannot fetch them directly; the plan is to copy the release files to the static host (Cloudflare Pages / R2) at deploy time and load them with `?model=<url>` or the app's own path. `meta.json` must then be pinned too: the app should carry the expected sha256 of `meta.json` (or of each file) in its own code, since today `meta.json` itself is trusted.
- Sample 8 and rank is affordable on desktop; mobile is unmeasured.
- Speed work should cut calls, not FLOPs.

## Follow-ups

- Fold the kind head into the decoder graph and run pitch/dur/finger heads in JS (or one fused call) to cut per-step calls from up to 5 to 1–2.
- Measure on a mid-range Android phone and iOS Safari (no threads without isolation).
- Release pipeline: upload export output to a GitHub Release, mirror to the static host, pin `meta.json`'s sha256 in the app.
- Run the melody-model tests in CI (needs torch CPU and node); the tests already fail instead of skip when `CI` is set.
- Port the rubric gate (`core/src/rubric.rs`) ranking into the browser once the Flutter path is chosen.
