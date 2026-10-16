---
# piano-sasu
title: Backing band parts (DRUMS, BASS) in play-along
status: completed
type: task
priority: normal
created_at: 2026-10-16T14:58:02Z
updated_at: 2026-10-16T15:03:21Z
parent: piano-eeut
---

## Context
Play-along has only piano ACC. Blocked by: none (builds on PR #12 feat/piano-sound).

## Higher Goal
Phase 1 play-along that feels like playing with a band.

## Acceptance Criteria
- [x] Content: optional DRUMS (GM 36/38/42/46/49) and BASS parts, linted, never graded
- [x] Core: TimedNote.part; companion_notes includes them; unit tests
- [x] Bridge: NoteView.part_name; FRB regenerated
- [x] Web audio: synthesized drums and bass, scheduled in play-along
- [x] Original drum/bass parts for ode-to-joy and hot-cross-buns
- [x] content-format spec + proposed decision D13

## Out of Scope
Native (non-web) audio; sampled drum kits; mixer/mute per part.

## Summary of Changes

- core: `Part` enum on `TimedNote`; `DRUMS` (GM 36/38/42/46/49, linted) and `BASS` parts are backing parts in `companion_notes`, never targets; tests.
- bridge: `NoteView.part_name`; FRB regenerated.
- web audio: synthesized drum kit and bass voice (`PianoSynth.drum/bass`), scheduled in play-along; negative schedule times clamped (threw and aborted scheduling).
- content: original drum/bass parts for ode-to-joy and hot-cross-buns; schema allows ACC/DRUMS/BASS.
- docs: content-format backing parts section; D13 proposed.
