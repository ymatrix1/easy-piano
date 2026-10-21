---
# piano-ddbv
title: Staff note edge fades
status: completed
type: task
created_at: 2026-10-21T20:00:22Z
updated_at: 2026-10-21T20:00:22Z
---

## Context
Reference app fades notes at the view edges; ours popped in/out at the clef. Blocked by: none.

## Higher Goal
Soft, readable scrolling staff.

## Acceptance Criteria
- [x] Notes fade in at right edge, fade out before clefs
- [x] Note at anchor always opaque (wait + play-along)
- [x] Grand staff band continuous; clefs crisp
- [x] flutter analyze + test pass

## Out of Scope
Slide-in motion, band/brace colour changes.

## Summary of Changes
Notes painted on a saveLayer masked by a dstIn horizontal gradient (StaffPainter.edgeFade); cull widened so notes fade fully; unit test; spec.
