# piano-h90n: Notation: ties, repeats, endings, key and meter changes

**Status:** todo  
**Type:** feature  
**Parent:** piano-bjig  

## Context
Pieces currently restrike tied notes, write repeats and D.C./D.S. out in full, and cannot change key or meter mid-song (e.g. Spanish Romance lost its major strain). Key signature at song start has been added (`key_signature.dart`), but mid-song changes, repeat barlines, voltas (1st/2nd endings), and navigation markers are required for authentic sheet reading (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/measurelayout.cpp`, `barline.cpp`, and `systemheaderlayout.cpp`.

Blocked by: none.

## Higher Goal
Read authentic sheet-music structure like standard method books and MuseScore scores teach.

## Acceptance Criteria
- [ ] Core play order expansion: `{repeat_start}`, `{repeat_end}`, `{volta: [1]}`, `{volta: [2]}`, `{dc_al_fine}`, `{coda}`, `{segno}`.
- [ ] Mid-measure / mid-piece key and time signature changes.
- [ ] Engraving rendering (`repeat_layout.dart`):
  - Repeat barlines with dual dots in staff spaces 2 and 3 (`|:` and `:|`).
  - Volta brackets above measures with number labels ("1.", "2.").
  - Mid-stream key signature and time signature cancellation/new signature layout.
- [ ] Core + lint + tests; app draws ties, repeat signs, endings, new key/time.
- [ ] Re-arrange songs that worked around these limitations (list from course-map known limits).
- [ ] Teaching lessons (scene + drill + song): repeat signs, 1st/2nd endings, D.C./D.S. al Fine and al Coda, key change and meter change inside a piece.

## Out of Scope
- Dynamics and pedal marks (`piano-boat`).

## Summary of Changes
*(To be completed upon finishing)*
