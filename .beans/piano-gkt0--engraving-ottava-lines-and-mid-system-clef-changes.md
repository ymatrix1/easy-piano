# piano-gkt0: Engraving: ottava lines and mid-system clef changes (MuseScore tlayout.cpp)

**Status:** todo  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
High piano passages avoid excessive ledger lines via $8^{va}$ (octave higher) or $8^{vb}$ (octave lower) spanners. Furthermore, when the left hand moves high or the right hand moves low, standard notation places a smaller clef mid-measure. MuseScore handles both in `references/MuseScore/src/engraving/rendering/score/tlayout.cpp` and `systemheaderlayout.cpp` (`docs/specs/sheet-engraving.md`).

Blocked by: none.

## Higher Goal
Maintain clean staff readability without ledger line clutter on extreme register piano passages.

## Acceptance Criteria
- [ ] Ottava lines: $8^{va}$ above treble and $8^{vb}$ below bass staff, followed by horizontal dashed line with downward/upward hook at the end.
- [ ] Pitch transposition: notes under ottava spanner adjust vertical staff step display while preserving sounding MIDI pitch.
- [ ] Mid-system clef changes: reduced-scale clef ($\approx 70\%$) inserted before the beat where hand register shifts.
- [ ] Dedicated helper `ottava_layout.dart` under `app/lib/ui/staff/`.
- [ ] Unit tests under `app/test/ui/staff/ottava_layout_test.dart`.

## Out of Scope
- $15^{ma}$ (two octaves) spanners.

## Summary of Changes
*(To be completed upon finishing)*
