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
- [ ] Traditional pedal marks: SMuFL $\mathfrak{Ped.}$ (U+E650) on down-pedal, $\ast$ (U+E655) on release.
- [ ] Modern bracket pedal lines: continuous horizontal line under the bass staff with vertical end hooks and inverted "V" notches at pedal change points (`___/\___|`).
- [ ] Automatic vertical offset to clear low notes and ledger lines.
- [ ] Dedicated helper `pedal_layout.dart` under `app/lib/ui/staff/`.
- [ ] Comprehensive unit tests under `app/test/ui/staff/pedal_layout_test.dart`.

## Out of Scope
- Half-pedaling and una corda / sostenuto pedal types.

## Summary of Changes
*(To be completed upon finishing)*
