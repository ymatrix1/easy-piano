---
# piano-3dp7
title: 'MuseScore engraving: smart beaming, accidental spacing, and notation polish'
status: completed
type: task
priority: normal
created_at: 2026-10-23T23:14:31Z
updated_at: 2026-10-23T23:28:57Z
parent: piano-eeut
---

## Context

The current staff rendering lacks note beaming for eighth and sixteenth notes, causing rapid runs (e.g. 16th notes) to render with overlapping individual flags that obscure the staff. In addition, tight subdivisions cause accidental collisions where sharps overlap preceding noteheads, clefs are clipped at the left screen edge, and time signatures lack optimal vertical clearance.

## Higher Goal

Bring sheet music engraving in Easy Piano up to MuseScore standards for piano notation, starting with intelligent beaming (connecting stem tips with solid angled/horizontal beams), accidental collision avoidance, clef margin breathing room, and proper time signature proportions, followed by ties, key signatures, and articulations.

## Acceptance Criteria

- [x] Consecutive eighth and sixteenth notes within metric beats are grouped and connected with primary and secondary beams
- [x] Individual flags are only drawn on isolated subdivision notes (unbeamed)
- [x] Accidental spacing prevents sharp/flat signs from overlapping preceding noteheads or stems in fast passages
- [x] Left staff margin (systemX) provides sufficient padding so treble clef flourishes are never clipped
- [x] Time signature digits have clean vertical separation and do not collide with each other on line 3
- [x] All Flutter unit tests pass and code is formatted cleanly

## Out of Scope

- Full orchestral multi-part engraving or guitar tablature
- Printing/publishing PDF pagination

## Summary of Changes

- Modularized `StaffPainter` into focused, DRY components:
  - `app/lib/ui/staff/smufl.dart`: dedicated SMuFL standard code points and digit mapping.
  - `app/lib/ui/staff/beam_layout.dart`: MuseScore-style `BeamGroup` and `BeamLayout` calculating metric beat grouping, unified stem direction, clamped slope, stem lengthening, primary beams, and secondary beams for 16th notes.
  - `app/lib/ui/staff/engraving_decorations.dart`: tapering Bézier ties (`drawTie`) and articulations (`drawArticulation` for staccato, tenuto, accent).
- Fixed accidental collision in `noteX` via sequential position caching (`xCache`), preventing accidentals from overlapping preceding notes in tight subdivisions.
- Fixed time signature digit overlap by scaling to `space * 3.4` with breathing room on line 3.
- Added comprehensive unit tests in `app/test/beam_layout_test.dart` verifying 16th note grouping, unbeamed isolated notes, and slope clamping. All 86 tests pass.
