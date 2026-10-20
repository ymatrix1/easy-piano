---
# piano-mtnq
title: Draw companion-hand notes on staff in single-hand stages
status: todo
type: task
created_at: 2026-10-16T19:49:51Z
updated_at: 2026-10-16T19:49:51Z
---

## Context
Found while checking Essentials III on web: in a RH-only stage on a grand-staff level (e.g. `e3-04-minuet`), the bass staff is empty although the song has LH notes the app plays as companion. `practice_stage.dart` builds staff notes only from session targets. Blocked by: none.

## Higher Goal
Students read the full score ("intro to full sheet music" in Essentials III) while practising one hand.

## Acceptance Criteria
- [ ] Companion-hand notes drawn (greyed, not graded) on the staff in single-hand stages
- [ ] Widget test covers it

## Out of Scope
Backing parts (ACC/DRUMS/BASS/PAD/CHOIR) on the staff.
