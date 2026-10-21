---
# piano-c5le
title: 'Audio engine stage 1: offline Rust sampler, mixer and parity test'
status: todo
type: task
created_at: 2026-10-21T20:26:44Z
updated_at: 2026-10-21T20:26:44Z
parent: piano-v8sj
---

## Context
Port the D22 web sound (sampler, round robin, soft hat, loop crossfade, buses, reverb, compressor, limiter, soft clipper, metronome click) into a new audio/ crate that renders to a buffer. Blocked by: none. Part of D30 (proposed).

## Higher Goal
Same realistic sound on every platform from one Rust engine.

## Acceptance Criteria
- [ ] audio/ crate renders event lists to PCM, pure and unit-tested
- [ ] Mix constants live in the engine (single source)
- [ ] Samples held as 16-bit with trimmed tails; decoded-sample memory measured before/after
- [ ] CI test renders Ode to Joy play-along: per-part RMS vs ACC within 2 dB of docs/research/instrument-samples.md, mix peak < 0 dBFS
- [ ] Event API from Dart (note, sample time, velocity, part) via flutter_rust_bridge

## Out of Scope
Platform output, web worklet.
