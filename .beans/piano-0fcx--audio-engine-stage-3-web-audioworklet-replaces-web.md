---
# piano-0fcx
title: 'Audio engine stage 3: web AudioWorklet replaces Web Audio graph'
status: todo
type: task
created_at: 2026-10-21T20:26:44Z
updated_at: 2026-10-21T20:26:44Z
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
- [ ] Same parity numbers as stage 1 measured in the browser
- [ ] Live key latency on web not worse than today (measured, same device and browser)
- [ ] Audio-thread CPU and first-load time not worse than today, measured on a named low-end device (browser keeps decoding MP3s; engine gets PCM)
- [ ] Fallback if any web gate fails: web keeps the Web Audio graph and matches native via the stage-1 parity test; record the outcome in D30
- [ ] Blind A/B listen vs current web by the user

## Out of Scope
Native.
