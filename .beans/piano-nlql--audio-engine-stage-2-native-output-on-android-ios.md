---
# piano-nlql
title: 'Audio engine stage 2: native output on Android, iOS and desktop'
status: todo
type: task
created_at: 2026-10-21T20:26:44Z
updated_at: 2026-10-21T20:26:44Z
parent: piano-v8sj
blocked_by:
    - piano-c5le
---

## Context
Play the stage-1 engine through cpal/Oboe/CoreAudio and wire PianoSynth to it on non-web platforms. Part of D30 (proposed).

## Higher Goal
Same realistic sound on every platform from one Rust engine.

## Acceptance Criteria
- [ ] Android, iOS and desktop play piano, band and metronome through the engine
- [ ] Engine output stream is the audio clock used by play-along
- [ ] Key-to-sound latency measured on one named Android and one named iOS device
- [ ] flutter test and analyze pass; app builds for Android and iOS

## Out of Scope
Web.
