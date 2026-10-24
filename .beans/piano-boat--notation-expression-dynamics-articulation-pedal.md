---
# piano-boat
title: ""
status: in-progress
type: task
priority: normal
created_at: 2026-10-24T18:51:13Z
updated_at: 2026-10-24T18:58:36Z
---

# piano-boat: Notation: expression (dynamics, articulation, pedal)

**Status:** in-progress (PR 1: dynamics and hairpins rendering)  
**Type:** feature  
**Parent:** piano-bjig  

## Context
Alfred and Faber teach dynamics ($p \dots ff$, crescendo/diminuendo hairpins), staccato, legato/slurs, accents, fermata and damper pedal from the first units; our notation engine now supports ties and articulations (`engraving_decorations.dart`), but dynamics, hairpins, and damper pedal lines remain to be rendered and graded (`docs/research/method-books-sequence.md`, `docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/dynamicslayout.cpp` and `pedal.cpp`.

Blocked by: none.

## Higher Goal
Teach learners how to play expressively, rendering standard professional score dynamics and pedals matching MuseScore standards.

## Acceptance Criteria
- [x] Spec & syntax for dynamics and hairpins: `{dyn:"p"}`, `{cresc}`, `{dim}`, `{end}` in song JSON (`docs/specs/content-format.md`). Token annotations for staccato/accent/fermata and `{ped}`/`{ped_up}` are not in this PR.
- [ ] Core parser + song model: Rust unit tests; grading rule per mark (velocity bands for MIDI, duration for staccato; mic: ignored or lenient). Not in PR 1: marks are rendered only.
- [x] Engraving rendering (`dynamics_layout.dart`, ref `dynamicslayout.cpp`, `tlayout.cpp` layoutHairpinSegment):
  - [x] SMuFL glyphs for `p pp ppp mp mf f ff fff fp sf sfz`, composed letter by letter as MuseScore `DYN_LIST` (U+E520 p, U+E521 m, U+E522 f, U+E524 s, U+E525 z).
  - [x] Crescendo/diminuendo hairpins drawn as two vector arms, `hairpinHeight` 1.15 sp, below the bottom staff at 1.75 sp.
  - [ ] Clearance from note stems (MuseScore places hairpins from the staff; stems of low notes can still cross them).
- [ ] Content lint rules and schema validation (reject unknown `{dyn}` text).
- [ ] Teaching lessons (animation scene + drill + song, strings in 5 locales) for each mark: dynamics $p/mp/mf/f/ff$, crescendo/diminuendo, staccato, legato/slur, accent, tenuto, fermata.

## Out of Scope
- Ties and repeats (covered by `piano-h90n`).
- Full damper pedal graphical bracket lines (covered by dedicated pedal bean).

## Summary of Changes
PR 1 (dynamics and hairpins, rendering only). Grading, lint and lessons are open in `piano-rdr4`.
- `app/lib/ui/staff/dynamics_layout.dart`: glyph composition, dynamic and hairpin placement, hairpin arms, barline clearance. Code points checked against the Bravura bbox metadata.
- `app/lib/ui/staff/song_marks_parser.dart`: reads `{dyn:"..."}`, `{cresc}`, `{dim}`, `{end}` from bars (same tokenizer as `SongRestParser`, now public).
- `app/lib/ui/staff/staff_painter.dart`: `dynamics` and `hairpins` params, drawn after notes inside the fade mask.
- `app/lib/practice/practice_stage.dart`: passes the parsed marks from the song JSON.
- Tests: `dynamics_layout_test.dart`, `song_marks_parser_test.dart`, `staff_dynamics_paint_test.dart`.
- Docs: `docs/specs/sheet-engraving.md` (parity row, section 1), `docs/specs/content-format.md` (directives).
