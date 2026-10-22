---
# piano-axwr
title: 'Audio engine stage 2b: device verification and audio clock for play-along'
status: todo
type: task
created_at: 2026-10-21T21:32:41Z
updated_at: 2026-10-21T21:32:41Z
parent: piano-v8sj
---

## Context
Stage 2 (piano-nlql) wired native sound and verified it on Windows desktop. Not verifiable from the dev machine: Android build (SDK licences not accepted, no device), iOS (needs a Mac), measured key-to-sound latency on real phones. Play-along still times notes with the MIDI clock, not the engine clock. Part of D30. Blocked by: none.

## Higher Goal
Same sound on phones, one audio clock (rule 7).

## Acceptance Criteria
- [ ] App builds and plays on one named Android device (integration_test/native_audio_test.dart passes)
- [ ] App builds and plays on one named iOS device
- [ ] Key-to-sound latency measured on both (same setup before/after)
- [ ] Play-along schedules against audioNowSec (engine clock) on native; grading unchanged
- [ ] Blind A/B web vs native listen by the user

## Out of Scope
Web AudioWorklet (piano-0fcx).
