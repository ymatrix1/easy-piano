---
# piano-unmb
title: ""
status: completed
type: task
priority: normal
created_at: 2026-10-24T21:38:54Z
updated_at: 2026-10-24T21:51:28Z
---

# piano-unmb: Engraving: piano damper pedal lines and traditional marks (MuseScore pedal.cpp)

**Status:** todo  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
Piano repertoire requires clear visual indications of damper pedal down, sustain, pedal changes, and releases. Currently, pedal events are only handled as audio events or omitted from visual rendering. MuseScore implements two standard conventions in `references/MuseScore/src/engraving/rendering/score/tlayout.cpp`: traditional glyphs ($\mathfrak{Ped.}$ / $\ast$) and modern bracket lines with retake notches (`docs/specs/sheet-engraving.md`).

Blocked by: none.

## Higher Goal
Render professional piano damper pedal indications matching MuseScore engraving standards.

## Acceptance Criteria
- [x] Traditional pedal marks: SMuFL $\mathfrak{Ped.}$ (U+E650) on down-pedal, $\ast$ (U+E655) on release.
- [x] Modern bracket pedal lines: continuous horizontal line under the bass staff with vertical end hooks and inverted "V" notches at pedal change points (`___/\___|`).
- [x] Automatic vertical offset to clear low notes and ledger lines.
- [x] Dedicated helper `pedal_layout.dart` under `app/lib/ui/staff/`.
- [x] Comprehensive unit tests under `app/test/ui/staff/pedal_layout_test.dart`.

## Out of Scope
- Half-pedaling and una corda / sostenuto pedal types.

## Summary of Changes
- `app/lib/ui/staff/pedal_layout.dart`: pure layout. `Ped.` / `*` glyphs, bracket line with change notches and release hook, vertical clearance from noteheads (`clearBelow`, shared with dynamics).
- `song_marks_parser.dart`: `{ped}` (press, or change while down) and `{ped-up}` (release) directives; `SongMarks.pedals`.
- `staff_painter.dart` / `practice_stage.dart`: draws pedal spans below the staff.
- Tests: `pedal_layout_test.dart` (new), `song_marks_parser_test.dart` and `staff_dynamics_paint_test.dart` (pedal cases).
- `docs/specs/sheet-engraving.md`, `docs/specs/content-format.md`: pedal section and directives.
- Deviations from MuseScore: change notches are a `/\` polyline, not MuseScore's two 45-degree hooks. The release hook height is `pedalHookHeight` (1.2 sp).
- Verified: `dart format` clean, `flutter analyze` clean, `flutter test` 208 passing, `python tools/check_tests.py` ok.
