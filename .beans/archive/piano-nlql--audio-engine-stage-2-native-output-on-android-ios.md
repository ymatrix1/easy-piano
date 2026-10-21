---
# piano-nlql
title: 'Audio engine stage 2: native output on Android, iOS and desktop'
status: completed
type: task
priority: normal
created_at: 2026-10-21T20:26:44Z
updated_at: 2026-10-21T21:32:43Z
parent: piano-v8sj
blocked_by:
    - piano-c5le
---



## Context
Play the stage-1 engine through cpal/Oboe/CoreAudio and wire PianoSynth to it on non-web platforms. Part of D30 (proposed).

## Higher Goal
Same realistic sound on every platform from one Rust engine.

## Acceptance Criteria
- [x] Event API from Dart (note, sample time, velocity, part, live note on/off, part levels) via flutter_rust_bridge
- [x] Android, iOS and desktop play piano, band and metronome through the engine (verified on Windows desktop; Android/iOS device runs moved to piano-axwr)
- [x] Engine output stream is the audio clock (`audioNowSec`); wiring play-along to it moved to piano-axwr
- [x] ~~Key-to-sound latency on named Android/iOS devices~~ moved to piano-axwr (no device here); Windows reports 10 ms output latency
- [x] flutter test and analyze pass; Windows desktop builds and passes the integration test (Android/iOS builds in piano-axwr)

## Out of Scope
Web.

## Summary of Changes
`audio/src/output.rs`: cpal output (WASAPI/CoreAudio/AAudio); the callback owns the engine, commands arrive over a channel, the frames rendered are the audio clock; live note on/off and bank swaps in the engine. Bridge `api/audio.rs` (native real, wasm no-op) and `PianoSynth` native implementation replacing the silent stub. Windows desktop target added. Measured on Windows (WASAPI shared, 48 kHz): reported output latency 10 ms, samples loaded 311 ms, audio clock 810 ms over 800 ms wall; `play_ode` example plays the fixture. Dependencies optimized in debug builds (an unoptimized engine starved the callback: 76 ms of audio per 800 ms).
