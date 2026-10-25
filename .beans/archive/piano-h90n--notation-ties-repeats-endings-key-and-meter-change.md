---
# piano-h90n
title: ""
status: completed
type: task
priority: normal
created_at: 2026-10-25T22:55:28Z
updated_at: 2026-10-25T23:33:36Z
---

---
# piano-h90n
title: ""
status: completed
type: task
priority: normal
created_at: 2026-10-25T22:55:28Z
updated_at: 2026-10-25T23:33:28Z
---

---
# piano-h90n
title: ""
status: in-progress
type: task
priority: normal
created_at: 2026-10-25T22:55:28Z
updated_at: 2026-10-25T22:56:37Z
---

# piano-h90n: Notation: ties, repeats, endings, key and meter changes

**Status:** completed (core structure, practice/study engraving, bar-start signatures, and Spanish Romance major strain restored)
**Type:** feature  
**Parent:** piano-bjig  

## Context
Pieces currently restrike tied notes, write repeats and D.C./D.S. out in full, and cannot change key or meter mid-song (e.g. Spanish Romance lost its major strain). Key signature at song start has been added (`key_signature.dart`), but mid-song changes, repeat barlines, voltas (1st/2nd endings), and navigation markers are required for authentic sheet reading (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/measurelayout.cpp`, `barline.cpp`, and `systemheaderlayout.cpp`.

Blocked by: none.

## Higher Goal
Read authentic sheet-music structure like standard method books and MuseScore scores teach.

## Acceptance Criteria
- [x] Core play order expansion: `{repeat_start}`, `{repeat_end}`, `{volta: [1]}`, `{volta: [2]}`, `{dc_al_fine}`, `{coda}`, `{segno}`.
- [x] Mid-piece key and time signature changes at bar starts; mid-bar changes remain unsupported by the content model.
- [ ] Engraving rendering (`repeat_layout.dart`):
  - [x] Repeat barlines with dual dots in staff spaces 2 and 3 (`|:` and `:|`).
  - [x] Volta brackets above measures with number labels ("1.", "2.").
  - [x] Mid-stream key signature and time signature layout at bar starts (cancellation naturals are a documented follow-up).
- [x] Core + lint + tests; app draws ties, repeat signs, endings, new key/time.
- [x] Restore the Spanish Romance major strain with a bar-start E major change and two repeated strains.

## Out of Scope
- Dynamics and pedal marks (`piano-boat`).

## Summary of Changes
This PR delivers notation structure, bar-start signature changes, and the Spanish Romance major strain. Lesson authoring is tracked by `piano-xhyb`; review of other existing arrangements is tracked by `piano-6fav`.

Delivered:
- Directive syntax (`content-format.md`, "Directives: repeats, voltas and navigation"): `{repeat_start}`, `{repeat_end}`, `{volta: [1]}`, `{volta: [2]}`, `{segno}`, `{coda}`, `{dc_al_fine}`. Added: `{volta_end}` (closes an ending without a hook) and `{ds_al_coda}`. Repeat and volta directives must sit on a bar line.
- Repeat barlines `|:`, `:|`, `:|:` (MuseScore `TDraw::draw(BarLine)` order), dots as `repeatDot` U+E044 in spaces 2 and 3 of each staff. They replace the plain bar line at their beat, and the end barline at `endBeat`.
- Volta brackets: line 3 sp above the top staff, hook at the left end, closed hook at the right end only when the ending closes with a repeat; "1." / "2." labels.
- Navigation marks: segno U+E047 and coda U+E048 (Leland); D.C. al Fine and D.S. al Coda as text (Leland has no dalSegno/daCapo).
- Code: `app/lib/ui/staff/repeat_layout.dart` (pure geometry), `song_marks_parser.dart` (parsing, new SongMarks fields with defaults), `staff_painter.dart` (new params with `const []` defaults, drawing), `practice_stage.dart` (wiring).
- Tests: `test/ui/staff/repeat_layout_test.dart` (geometry and paint), `song_marks_parser_test.dart` (directive parsing, malformed input ignored).

Delivered in this PR:
- Core expands repeats twice, selects first/second endings, follows D.C./D.S. al Fine / al Coda once, and expands critical sections to played bars.
- Core ties extend one performance target without re-strike; app draws the continuation heads and tie curves.
- Song JSON `changes` applies validated key and meter updates at the beginning of one-based bars. Core timing, score study measure partitioning, practice barlines, and signature display use the new starts.
- Lint validates repeat/volta positions, nesting, and signature changes; schema and specs document the format and mid-bar limitation.
- Difficulty analysis evaluates notes against the effective key of each bar; the learned skill set includes keys introduced mid-song.
- The Spanish Romance E major strain (Mutopia guitar edition, [CC BY-SA 2.5](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=795)) is restored as an original piano arrangement, with both 16-bar strains repeated.
- Tests cover repeat/navigation order, ties, signature timing, effective-key difficulty, parser data, variable measures, and signature engraving.
