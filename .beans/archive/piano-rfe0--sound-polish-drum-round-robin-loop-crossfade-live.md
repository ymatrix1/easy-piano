---
# piano-rfe0
title: 'Sound polish: drum round robin, loop crossfade, live clip guard'
status: completed
type: task
priority: normal
created_at: 2026-10-21T16:37:37Z
updated_at: 2026-10-21T16:37:38Z
---

## Context
Follow-up review of PR #49 (D22): repeated drum hits, possible pad/choir loop clicks, live chords may clip. Blocked by: none.

## Higher Goal
Realistic, clean sound in play-along and free play.

## Acceptance Criteria
- [x] Round-robin kick/snare/hat hits and a soft hat layer
- [x] Crossfaded sustain loops, measured at the seam
- [x] Live chord peak under 0 dBFS without added latency
- [x] Measurements in docs/research/instrument-samples.md

## Out of Scope
Velocity layers, native audio.

## Summary of Changes
7 Virtuosity hits (+54 KB), round robin + soft hat in piano_synth_web.dart, 150 ms equal-power loop crossfade, WaveShaper soft clipper at the output, probe gains liveChord and pad seam metrics. Live chord peak +1.6 -> -0.7 dBFS; seam jump 2.13 -> 1.48 dB.
