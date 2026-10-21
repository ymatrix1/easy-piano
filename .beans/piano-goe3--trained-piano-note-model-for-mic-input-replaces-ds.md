---
# piano-goe3
title: Trained piano-note model for mic input (replaces DSP when it beats it)
status: in-progress
type: task
created_at: 2026-10-21T22:21:09Z
updated_at: 2026-10-21T22:21:09Z
parent: piano-kxi3
---

## Context
PR #40's DSP note detector hits diminishing returns: users report false notes from voices/noise and double notes. A small streaming CNN (onset + frame, 88 keys) trained on license-clean synthetic piano data plus MAESTRO excerpts may beat it. Blocked by: PR #40 (feat/mic-input).

## Higher Goal
Mic play that ignores room noise and speech and reports each note once, in a browser, on the free web build.

## Acceptance Criteria
- [ ] Extra piano sets (CC0/CC-BY) verified and documented; fixtures per piano; DSP scored per piano
- [ ] Data generator, streaming model, ONNX export in tools/mic-model/
- [ ] Offline P/R/F1, false notes/min, phantom passes, latency vs DSP on held-out data, blind and score modes
- [ ] Web integration behind a switch, DSP fallback, per-frame compute measured in Chrome
- [ ] Docs, decision (proposed), flutter analyze + test pass

## Out of Scope
Real-recording evaluation on the student's own piano and phones (piano-m4r9); native Android/iOS runtime; Rust core port (OQ11).
