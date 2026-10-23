---
# piano-unv4
title: 'Staff: bar line spacing before eighth notes and density in wait mode'
status: completed
type: bug
priority: normal
created_at: 2026-10-23T12:07:37Z
updated_at: 2026-10-23T12:14:52Z
parent: piano-eeut
---

## Context
In wait and play-along stages, bar lines were placed at a fixed offset of -0.8 spaces before the bar start beat. When an eighth note precedes the bar line (e.g. beat 3.5 in Oh Susanna), its upward stem sits at +1.18 spaces, leaving only ~7 px of gap between the stem and the bar line at 70 ppb. Additionally, wait mode forced ppb to clamp to minPpb (70), over-compressing eighth notes on longer pieces.

## Higher Goal
Notation on the scrolling and paging staff should look legible and well-spaced, with balanced margins around bar lines and sufficient horizontal breathing room for eighth notes.

## Acceptance Criteria
- [x] Bar line x position balances the gap between the preceding note (stem/head right edge) and the following note (or bar start), avoiding collisions with eighth notes
- [x] Scores containing eighth notes (or smaller durations) maintain a higher minimum ppb in wait mode so subdivisions remain clear and legible
- [x] Tests in app/ pass and verify bar line placement does not collide with preceding notes

## Out of Scope
- Changing music fonts or full non-linear sheet engraving engine

## Summary of Changes
- Added `StaffPainter.barLineX` helper that detects preceding notes (considering notehead/stem width, accidentals, dots) and balances the bar line symmetrically when the visual gap is tight (such as before eighth notes), preventing bar lines from colliding with stems or accidentals.
- Updated `PracticeStage._fitPage` to use a minimum density of 95 ppb (instead of 70 ppb) for scores containing subdivisions (`beats < 1.0`), ensuring eighth notes receive proper horizontal breathing room in wait mode.
- Added comprehensive unit tests in `app/test/staff_painter_test.dart` covering nominal bar line offset, balanced positioning before eighth notes, and accidental avoidance.
