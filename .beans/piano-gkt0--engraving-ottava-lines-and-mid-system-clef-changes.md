# piano-gkt0: Engraving: ottava lines and mid-system clef changes (MuseScore tlayout.cpp)

**Status:** in-progress  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
High piano passages avoid excessive ledger lines via $8^{va}$ (octave higher) or $8^{vb}$ (octave lower) spanners. Furthermore, when the left hand moves high or the right hand moves low, standard notation places a smaller clef mid-measure. MuseScore handles both in `references/MuseScore/src/engraving/rendering/score/tlayout.cpp` and `systemheaderlayout.cpp` (`docs/specs/sheet-engraving.md`).

Blocked by: none.

## Higher Goal
Maintain clean staff readability without ledger line clutter on extreme register piano passages.

## Acceptance Criteria
- [x] Ottava lines: $8^{va}$ above treble and $8^{vb}$ below bass staff, followed by horizontal dashed line with downward/upward hook at the end.
- [x] Pitch transposition: notes under ottava spanner adjust vertical staff step display while preserving sounding MIDI pitch.
- [ ] Mid-system clef changes: reduced-scale clef ($\approx 70\%$) inserted before the beat where hand register shifts. Not delivered. MuseScore `smallClefMag` is 0.8, not 0.7 (`legacy-style-defaults-v450.mss:380`). Re-reading the notes after a clef change is a separate change (see `docs/specs/sheet-engraving.md`, module 6).
- [x] Dedicated helper `ottava_layout.dart` under `app/lib/ui/staff/`.
- [x] Unit tests under `app/test/ui/staff/ottava_layout_test.dart`.

## Out of Scope
- $15^{ma}$ (two octaves) spanners.

## Summary of Changes
- `app/lib/ui/staff/ottava_layout.dart`: `OttavaKind` (shift +12 / -12, `dom/ottava.h:68-69`), `StaffOttava`, line y (-2 sp / +2 sp, mss:540-541), hook (1 sp towards the staff, mss:542), dash spans (6 / 6 line widths, tdraw.cpp:1593-1598), `displayPitch` and `displayNotes` (pitch shown at `pitch - shift`, sounding pitch kept).
- `song_marks_parser.dart`: `{ottava:"8va"}`, `{ottava:"8vb"}`, `{ottava_end}` per hand; `SongMarks.ottavas` (default `[]`).
- `staff_painter.dart`: `ottavas` parameter; notes re-pitched in the constructor; bursts use the displayed pitch; dashed line and hook drawn in the marks block.
- `practice_stage.dart`: passes `ottavas`.
- Tests: `ottava_layout_test.dart`, parser cases in `song_marks_parser_test.dart`, `staff_ottava_paint_test.dart` (ink at the computed line and hook, by difference from a render without the ottava).
- Not done: mid-system small clef (see criteria); `8va` text label; collision avoidance; 15ma. Details and sources in `docs/specs/sheet-engraving.md` (module 6) and `docs/specs/content-format.md`.
