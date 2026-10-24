---
# piano-5wx1
title: 'Staff engraving polish: smart fingerings, accidental spacing, staff band padding, and wait density'
status: completed
type: task
created_at: 2026-10-23T14:33:48Z
updated_at: 2026-10-23T19:05:00Z
parent: piano-eeut
---

## Context
User feedback and screenshots showed several visual defects in sheet rendering:
1. Finger numbers printed above every single note created extreme visual clutter.
2. Accidentals on short-duration notes collided with preceding noteheads.
3. The staff band tightly wrapped 5 lines, leaving middle C (ledger line) in the purple background.
4. Wait mode fitPage crammed entire songs (30+ notes) on a single screen without pagination limits.

## Higher Goal
Transform the staff presentation into professional engraving standards following Faber, Alfred, and Simply Piano references.

## Acceptance Criteria
- [x] Finger numbers only show on current note badge, first note of a piece, or when hand/finger position changes
- [x] Accidentals allocate horizontal clearance so glyphs do not collide with preceding noteheads
- [x] Staff band and heavy rectangle frame include vertical padding (1.5-2 spaces) so Middle C and ledger notes remain inside the band
- [x] Wait mode limits visible measures per screen (e.g. 3-4 measures) maintaining comfortable horizontal density with smooth paging
- [x] All tests in app/ pass and formatting/analyzer are clean

## Out of Scope
- Full beam grouping algorithms and complex curved slurs (deferred to Etapa 2)

## Summary of Changes
- Added `noteX()` in `StaffPainter` to detect collision with preceding notes and ensure accidentals have proper horizontal clearance.
- Added vertical padding (`vPad = space * 1.5`) to `staffSpans` in `StaffPainter.paint` so Middle C and standard ledger notes sit comfortably inside the white staff band.
- Added smart finger filtering in `_shouldDrawFinger()`: displays finger on active badge, first note for a hand, on finger change, or when hand position jumps >= 5 semitones or after large phrase rests.
- Capped wait mode `_fitPage` density in `PracticeStage` to at most 4 measures per screen (`math.min(_totalBeats, _beatsPerBar * 4.0)`).
- Added unit tests for `noteX()` accidental spacing in `staff_painter_test.dart`. All 81 app tests pass with zero analyzer warnings.
