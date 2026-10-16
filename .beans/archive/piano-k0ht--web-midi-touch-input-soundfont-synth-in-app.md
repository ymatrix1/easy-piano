---
# piano-k0ht
title: Web MIDI + touch input + soundfont synth in app
status: completed
type: task
priority: normal
created_at: 2026-10-16T04:51:30Z
updated_at: 2026-10-16T14:42:04Z
parent: piano-eeut
---



## Context
Phase 1 (docs/ROADMAP.md). Builds on MIDI spike. Blocked by: none.
## Higher Goal
First playable web version (D9).
## Acceptance Criteria
- [x] Delivered and verified, ROADMAP box ticked
- [x] Piano sound on/off toggle: on by default with a MIDI controller or the on-screen keyboard, off for digital pianos with their own speakers; remembered per device
- [x] Pre-listen and wait-stage demo (light beam sweep) play through the synth
## Out of Scope
Other Phase 1 items.

## Summary of Changes

- Samples: 21 FluidR3_GM grand piano MP3s (MIT, via midi-js-soundfonts) in `app/assets/piano/` with license and README.
- `app/lib/audio/`: `PianoSynth` (Web Audio sample player with pitch shift, release fade, scheduling, metronome click; silent stub off-web), shared `pianoSynth`.
- Practice screen: student keys sound; top-bar sound toggle remembered in localStorage; pre-listen demo (dimmed staff, beam and highlight walk the notes, Skip, input ignored, clock starts after); play-along companion (other hand + `ACC`) or metronome, one-bar count-in clicks, pause stops / resume reschedules.
- Core: `ACC` accompaniment part (never a target) and `companion_notes`; bridge `companion()`.
- Content: `ACC` parts for Hot Cross Buns and Ode to Joy (own arrangements).
- Verified: core 44 unit + 6 integration tests, flutter 10 tests, analyze clean, content lint ok; in Chrome the demo runs (banner, dim, beam) and samples load without console errors. Audio itself was not heard by the agent.
