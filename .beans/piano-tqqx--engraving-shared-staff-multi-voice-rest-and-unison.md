# piano-tqqx: Engraving: shared staff multi-voice rest and unison layout (MuseScore stavesharinglayout.cpp)

**Status:** todo  
**Type:** feature  
**Parent:** piano-r9p5  

## Context
When two independent voices exist on the same staff (e.g. polyphonic classical pieces, Bach, Schumann), Voice 1 stems point UP and Voice 2 stems point DOWN. Beyond stem direction, MuseScore handles rest elevation (Voice 1 rests pushed to upper staff spaces, Voice 2 rests to lower spaces) and notehead sharing on simultaneous unisons in `references/MuseScore/src/engraving/rendering/score/stavesharinglayout.cpp` (`docs/specs/sheet-engraving.md`).

Blocked by: none.

## Higher Goal
Render clean, readable polyphonic piano textures without colliding rests or redundant duplicate noteheads.

## Acceptance Criteria
- [ ] Voice-specific rest positioning: Voice 1 rests elevate by +2 to +4 staff steps; Voice 2 rests descend by -2 to -4 staff steps.
- [ ] Simultaneous unisons: notes of identical pitch and duration between Voice 1 and Voice 2 share a single notehead with two opposing stems (one up, one down).
- [ ] Different durations on unisons: noteheads with different head types (e.g. half note and quarter note) drawn side-by-side without collision.
- [ ] Dedicated helper `voice_sharing_layout.dart` under `app/lib/ui/staff/`.
- [ ] Unit tests under `app/test/ui/staff/voice_sharing_layout_test.dart`.

## Out of Scope
- More than 2 voices per staff.

## Summary of Changes
*(To be completed upon finishing)*
