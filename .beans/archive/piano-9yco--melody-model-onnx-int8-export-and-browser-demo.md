---
# piano-9yco
title: 'Melody model: ONNX int8 export and browser demo'
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-21T02:30:29Z
updated_at: 2026-10-21T02:42:30Z
parent: piano-bovj
blocked_by:
    - piano-blr4
---


## Context
Step 5 of the melody model (D20). Training code exists (piano-blr4). Blocked by: piano-blr4 (checkpoints).

## Higher Goal
Generate original practice tunes per course node in the browser, offline, with no server.

## Acceptance Criteria
- [x] melody_model/export.py: one-step decoder graph with KV cache, cascaded heads callable field by field, int8 dynamic quantization
- [x] Parity test vs PyTorch logits (fp32 and int8 tolerance); model size in MB
- [x] Browser demo tools/melody-model/web/: spec prefix, masked decoding (kind grammar, range, durations, bar overflow, CHORD/TIE), decode to song JSON, playback
- [x] Chrome desktop measurements (download size, load time, ms per 8-bar tune) in docs/research/melody-browser.md and spec section

## Out of Scope
- Training changes, dataset changes, rubric gate in browser, Flutter integration

## Summary of Changes
- `melody_model/export.py`: KV-cache decoder graph + cascaded heads graph, fp32 and int8 (dynamic quantization), parity check, meta.json. Decoder int8 11.72 MB (fp32 43.51 MB), heads 0.76 MB.
- `tests/test_export.py` (parity, batch 2), `tests/test_web.py` + `web/check.mjs` (JS spec/decode vs Python, masked generation obeys spec).
- `web/`: index.html, melody.js (spec prefix, grammar masks, sampling, decode), serve.py (COOP/COEP).
- Chrome 155 desktop: int8 load 0.5–1.2 s, 8-bar tune 0.25–0.42 s, batch of 8 2.0–2.5 s; overhead-bound. `docs/research/melody-browser.md`, spec section.

