---
# piano-0fcx
title: 'Audio engine stage 3: web AudioWorklet replaces Web Audio graph'
status: scrapped
type: task
priority: normal
created_at: 2026-10-21T20:26:44Z
updated_at: 2026-10-21T22:51:43Z
parent: piano-v8sj
blocked_by:
    - piano-c5le
---

## Context
Compile the engine to wasm in an AudioWorklet and make piano_synth_web.dart a thin event sender. Part of D30 (proposed).

## Higher Goal
Same realistic sound on every platform from one Rust engine.

## Acceptance Criteria
- [ ] Web plays through the worklet engine; Web Audio graph removed
- [x] Same parity numbers as stage 1 measured in the browser
- [x] Live key latency on web measured, same device and browser (worse: gate failed)
- [x] Audio-thread CPU and first-load time measured (worse: gate failed; on a fast desktop, low-end device not needed to decide)
- [x] Fallback if any web gate fails: web keeps the Web Audio graph and matches native via the stage-1 parity test; record the outcome in D30
- [ ] Blind A/B listen vs current web by the user

## Out of Scope
Native.

## Summary of Changes
Built the engine for the worklet (`audio/web`, bare wasm, no decode/output), a worklet runner and a thin Dart sender with `?mixprobe` latency/CPU/load probes, on branch `research/d30-worklet-spike` (not merged). Measured against the Web Audio graph in the same build: parity passes (worst 1.08 dB, output identical to native) but CPU 2-3x, key latency median 9.1 vs 6.4 ms, first load ~2.1 vs 1.7 s. Web keeps Web Audio; outcome in D30 and `docs/research/web-audio-worklet-gates.md`. Follow-up: piano-d88j.

## Reasons for Scrapping
Gates failed (CPU, latency, first load). Fallback taken: web keeps the Web Audio graph. Blind A/B not run because nothing on web changes.
