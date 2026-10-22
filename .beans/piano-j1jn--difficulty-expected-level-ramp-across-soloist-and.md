---
# piano-j1jn
title: 'Difficulty: expected-level ramp across Soloist and Chords tracks'
status: todo
type: task
created_at: 2026-10-22T19:29:42Z
updated_at: 2026-10-22T19:29:42Z
parent: piano-7m8d
---

## Context
The proposed linear ramp (D26) maps the whole courses.json walk to levels 1..6, so advanced courses expect ~6 and most new songs rate 3-7; lint warnings no longer mean much past Essentials. Blocked by: none.

## Higher Goal
Content level warnings that guide authors in late courses.

## Acceptance Criteria
- [x] Proposed rule for expected level per track/course depth (decision update, proposed)
- [x] level.rs ramp implemented and tested
- [ ] Calibration rerun with track songs; raise course_levels[1] above 6
- [ ] Lint warnings reviewed for the 27 new courses

## Out of Scope
- Re-arranging songs
