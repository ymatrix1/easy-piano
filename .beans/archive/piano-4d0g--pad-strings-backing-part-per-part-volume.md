---
# piano-4d0g
title: PAD (strings) backing part + per-part volume
status: completed
type: task
created_at: 2026-10-16T17:16:09Z
updated_at: 2026-10-16T17:16:09Z
parent: piano-eeut
---

## Context
Follow-up to piano-sasu (DRUMS/BASS). Blocked by: none.

## Higher Goal
Fuller play-along mix that can be balanced.

## Acceptance Criteria
- [x] PAD part in core, lint, schema, tests
- [x] Web pad voice (detuned saws, slow envelope), no samples
- [x] Per-part gain buses with default mix and setPartLevel()
- [x] PAD parts for ode-to-joy and hot-cross-buns
- [x] Spec + D13 addendum (proposed)

## Out of Scope
Mixer/mute UI; native audio.

## Summary of Changes
Part::Pad in core; PianoSynth.pad() and setPartLevel(); _scheduleBacking routes PAD and tags ACC with its bus; songs and docs updated.
