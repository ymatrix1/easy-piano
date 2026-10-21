# Melody model in the browser

Checked: 2026-10-20. Sources: own measurements (below), onnxruntime-web 1.30.0 (jsdelivr, `latest` tag on that date), onnxruntime 1.31.0 quantization (`quantize_dynamic`), torch 2.11 legacy ONNX exporter.

Question: can the step-4 melody model (11.09M params, D20) run in a browser tab fast enough to generate practice tunes on demand, and at what download cost?

## Setup

| Item | Value |
|---|---|
| Machine | this dev desktop, Windows 11, 32 logical cores, Chrome 155 (desktop, user's browser via Claude in Chrome) |
| Server | `python tools/melody-model/web/serve.py` on localhost (COOP/COEP set, so `crossOriginIsolated` = true), `Cache-Control: no-store` |
| Runtime | onnxruntime-web 1.30.0, `ort.wasm.min.mjs`, wasm EP, graph optimization `all` |
| Model | `smoke3` checkpoint (speed does not depend on the weights; same graph shape as `base1`) |
| Spec | 4/4, C, 8 bars, RH, range C4–C5, durations 2 and 4 |
| Decoding | masked (`web/melody.js`), temperature 1.0, KV cache, heads called once per field that has a real choice |

Method: `window.loadModel()` timed with `performance.now()` from the click to both sessions ready (fetch + session create). Byte counts from `performance.getEntriesByType("resource")` (`transferSize`). `window.bench({runs: 5, n})`: one warm-up generation, then 5 generations with seeds 1–5; median reported. Tune length varies with the sample (68–105 decode steps after the spec prefix).

## Results

| Variant | Threads | Download (model) | Load | n = 1: ms per tune | n = 8: ms per batch | n = 8: ms per tune |
|---|---|---|---|---|---|---|
| int8 | 1 | 12.48 MB | 1,225 ms (first load, incl. wasm compile) | 419 | 2,528 | 316 |
| int8 | 4 | 12.48 MB | 545 ms | 333 | 2,032 | 254 |
| fp32 | 1 | 44.72 MB | 449 ms | 574 | 2,037 | 255 |

Also downloaded once: onnxruntime-web wasm 3.07 MB, JS 0.03 MB.

| File | MB |
|---|---|
| `decoder.onnx` / `decoder.int8.onnx` | 43.51 / 11.72 |
| `heads.onnx` / `heads.int8.onnx` | 1.21 / 0.76 |

Parity (`melody_model/export.py`, Ode to Joy, teacher-forced through the KV-cache path, ORT CPU vs PyTorch full sequence):

| Checkpoint | fp32 max abs logit diff | int8 max prob diff | int8 top-1 agreement |
|---|---|---|---|
| smoke3 (step 1,087) | 9.5e-6 | 0.020 | 97.9% |
| base1 (step 6,000, val loss 1.02) | 1.5e-5 | 0.020 | 100% |

Sample (base1 step 6,000, int8, spec above with durations 2/4/8, best of 8 by mean log p), RH per bar:
`A4:4 A4:4 A4:4 E4:4 | D4:4 E4:4 C4:2 | G4:4 G4:8 A4:8 G4:4 E4:4 | D4:4 E4:4 D4:2 | C4:4 C4:4 C4:4 C4:4 | G4:4 G4:4 A4:2 | G4:4 G4:8 A4:8 G4:4 E4:4 | D4:4 E4:4 C4:2`. All 8 candidates finished; every bar is full by construction.

## Findings

- An 8-bar tune takes ~0.25–0.4 s; a batch of 8 candidates ~2–2.5 s. Usable for "generate on node open" behind a short spinner, or precomputed in the background.
- fp32 and int8 run at the same speed, and 4 threads help only ~20%: time is dominated by per-call overhead (one decoder call plus up to four heads calls per step, ~100 steps), not by matmuls.
- int8 cuts the download 3.5x (44.7 → 12.5 MB) with no measurable quality loss on the parity check.

## Implications

- Ship int8. 12.5 MB + 3 MB wasm is acceptable as a lazily downloaded, cached asset (not in the first-load bundle).
- Sample 8 and rank is affordable on desktop; mobile is unmeasured.
- Speed work should cut calls, not FLOPs.

## Follow-ups

- Fold the kind head into the decoder graph and run pitch/dur/finger heads in JS (or one fused call) to cut per-step calls from up to 5 to 1–2.
- Measure on a mid-range Android phone and iOS Safari (WebAssembly SIMD, no threads without isolation).
- Port the rubric gate (`core/src/rubric.rs`) ranking into the demo once the Flutter path is chosen.
- Re-run the sample with the final `base1` checkpoint.
