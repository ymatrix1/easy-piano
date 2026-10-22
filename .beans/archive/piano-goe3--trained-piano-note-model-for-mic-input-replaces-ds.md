---
# piano-goe3
title: Trained piano-note model for mic input (replaces DSP when it beats it)
status: completed
type: task
priority: normal
created_at: 2026-10-21T22:21:09Z
updated_at: 2026-10-22T11:37:29Z
parent: piano-kxi3
---


## Context
PR #40's DSP note detector hits diminishing returns: users report false notes from voices/noise and double notes. A small streaming CNN (onset + frame, 88 keys) trained on license-clean synthetic piano data plus MAESTRO excerpts may beat it. Blocked by: PR #40 (feat/mic-input).

## Higher Goal
Mic play that ignores room noise and speech and reports each note once, in a browser, on the free web build.

## Acceptance Criteria
- [x] Extra piano sets (CC0/CC-BY) verified and documented; fixtures per piano; DSP scored per piano
- [x] Data generator, streaming model, ONNX export in tools/mic-model/
- [x] Offline P/R/F1, false notes/min, phantom passes, latency vs DSP on held-out data, blind and score modes
- [x] Web integration behind a switch, DSP fallback, per-frame compute measured in Chrome
- [x] Docs, decision (proposed), flutter analyze + test pass

## Out of Scope
Real-recording evaluation on the student's own piano and phones (piano-m4r9); native Android/iOS runtime; Rust core port (OQ11).

## Summary of Changes
- `tools/mic-model/`: piano sets (Salamander, FreePats KW, FreePats YDP held out; MAESTRO v3.0.0 subset) fetched with pinned hashes, endless training-data generator, streaming CNN with exact step/sequence equivalence, training, ONNX export, evaluation tools, parity tests. `tools/mic_fixtures.py` and `app/tool/mic_eval.dart` score per piano and variant.
- Shipped model: 20,842 parameters, 102 KiB ONNX. Beats the DSP detector on every held-out set (score-informed F1 0.990 vs 0.935 synthetic, 0.80 vs 0.42 real MAESTRO audio, 0.82 vs 0.45 piano under TTS speech; false notes 0.0 vs 57.5 per minute on typing/chatter/hum/knocks and 7 vs 142 on speech).
- Web: `app/web/mic_model_core.js` and `mic_model_worker.js` (onnxruntime-web 1.30.0, shared with practice mode's pinned vendor copy), wired into `MicInput` behind `modelEnabled` / `?mic=dsp`, DSP fallback. about 1 ms per 16 ms frame in desktop Chrome; verified in the built app (ORT 1.27.0) and on the test page (ORT 1.30.0).
- Docs: research section with data licences, method and results, input spec, D32 (proposed), OQ11 note, ROADMAP item.
- Not done: real-recording and phone evaluation (piano-m4r9); the shipped weights were partly trained on CC BY-NC-SA MAESTRO audio (D32 asks the user to decide).
