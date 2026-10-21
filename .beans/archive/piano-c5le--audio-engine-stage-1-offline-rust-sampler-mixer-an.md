---
# piano-c5le
title: 'Audio engine stage 1: offline Rust sampler, mixer and parity test'
status: completed
type: task
priority: normal
created_at: 2026-10-21T20:26:44Z
updated_at: 2026-10-21T20:55:32Z
parent: piano-v8sj
---


## Context
Port the D22 web sound (sampler, round robin, soft hat, loop crossfade, buses, reverb, compressor, limiter, soft clipper, metronome click) into a new audio/ crate that renders to a buffer. Blocked by: none. Part of D30 (proposed).

## Higher Goal
Same realistic sound on every platform from one Rust engine.

## Acceptance Criteria
- [x] audio/ crate renders event lists to PCM, pure and unit-tested
- [x] Mix constants live in the engine (single source)
- [x] Samples held as 16-bit with trimmed tails; decoded-sample memory measured before/after
- [x] CI test renders Ode to Joy play-along: per-part RMS vs ACC within 2 dB of docs/research/instrument-samples.md, mix peak < 0 dBFS
- [x] ~~Event API from Dart via flutter_rust_bridge~~ moved to stage 2 (piano-nlql): nothing consumes it until there is an output

## Out of Scope
Platform output, web worklet.

## Summary of Changes
New `audio/` crate (MPL-2.0; deps rustfft MIT/Apache-2.0, symphonia MPL-2.0 behind the `decode` feature): sample bank (16-bit, tails trimmed at -60 dB / 10 s, crossfaded loops), engine with sample-accurate events, round robin, soft hat, hi-hat choke, piano velocity low-pass, per-part buses, partitioned-FFT convolution reverb with Web Audio normalization, glue compressor and limiter with Web Audio-style makeup, soft clipper. Parity test on the web-exported Ode to Joy fixture: worst part balance 1.08 dB vs web (gate 2 dB), mix peak -0.82 dBFS; memory 66 MB vs 183 MB on web. 16 tests; CI runs fmt, clippy, test. Web app gains `window.epDumpEvents()` (with `?mixprobe`) and `RecordingSynth` to re-export the fixture.
