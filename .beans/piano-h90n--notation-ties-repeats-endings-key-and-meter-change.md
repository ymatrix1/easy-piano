# piano-h90n: Notation: ties, repeats, endings, key and meter changes

**Status:** in-progress (PR 5: repeat barlines, voltas and navigation rendering)  
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
  - [x] Repeat barlines with dual dots in staff spaces 2 and 3 (`|:` and `:|`).
  - [x] Volta brackets above measures with number labels ("1.", "2.").
  - [ ] Mid-stream key signature and time signature cancellation/new signature layout.
- [ ] Core + lint + tests; app draws ties, repeat signs, endings, new key/time.
- [ ] Re-arrange songs that worked around these limitations (list from course-map known limits).
- [ ] Teaching lessons (scene + drill + song): repeat signs, 1st/2nd endings, D.C./D.S. al Fine and al Coda, key change and meter change inside a piece.

## Out of Scope
- Dynamics and pedal marks (`piano-boat`).

## Summary of Changes
PR 5 (rendering only). The bean stays in progress: play order, key/meter changes, lint, lessons and re-arrangement are open.

Delivered:
- Directive syntax (`content-format.md`, "Directives: repeats, voltas and navigation"): `{repeat_start}`, `{repeat_end}`, `{volta: [1]}`, `{volta: [2]}`, `{segno}`, `{coda}`, `{dc_al_fine}`. Added: `{volta_end}` (closes an ending without a hook) and `{ds_al_coda}`. Repeat and volta directives must sit on a bar line.
- Repeat barlines `|:`, `:|`, `:|:` (MuseScore `TDraw::draw(BarLine)` order), dots as `repeatDot` U+E044 in spaces 2 and 3 of each staff. They replace the plain bar line at their beat, and the end barline at `endBeat`.
- Volta brackets: line 3 sp above the top staff, hook at the left end, closed hook at the right end only when the ending closes with a repeat; "1." / "2." labels.
- Navigation marks: segno U+E047 and coda U+E048 (Leland); D.C. al Fine and D.S. al Coda as text (Leland has no dalSegno/daCapo).
- Code: `app/lib/ui/staff/repeat_layout.dart` (pure geometry), `song_marks_parser.dart` (parsing, new SongMarks fields with defaults), `staff_painter.dart` (new params with `const []` defaults, drawing), `practice_stage.dart` (wiring).
- Tests: `test/ui/staff/repeat_layout_test.dart` (geometry and paint), `song_marks_parser_test.dart` (directive parsing, malformed input ignored).

Remaining:
- Core play-order expansion: `{repeat_*}`, endings, D.C. / D.S. and coda jumps change the play order in core and the play-along (no playback change yet).
- Mid-piece key and time signature changes, including their engraving (cancellation and new signature).
- Lint for the new directives, and teaching lessons (scene, drill, song).
- Re-arranging songs that worked around these limits.
