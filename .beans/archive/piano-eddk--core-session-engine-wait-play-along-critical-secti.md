---
# piano-eddk
title: 'Core session engine: wait, play_along, critical sections, stars'
status: completed
type: task
priority: normal
created_at: 2026-10-16T04:51:30Z
updated_at: 2026-10-16T05:01:05Z
parent: piano-eeut
blocked_by:
    - piano-s5pb
---


## Context
Phase 1 (docs/ROADMAP.md). Spec: docs/specs/exercise-engine.md.
## Higher Goal
First playable web version (D9).
## Acceptance Criteria
- [x] Delivered and verified, ROADMAP box ticked
## Out of Scope
Other Phase 1 items.

## Summary of Changes

`core/src/session.rs`: Wait and PlayAlong modes, per-input hit windows (MIDI 150 ms, mic/touch 200 ms), chords, misses, wrong notes, critical sections with adaptive threshold, stars, practice-mode hint. 10 unit tests + `core/tests/lessons_playable.rs` over all lesson songs. Spec updated to match.
