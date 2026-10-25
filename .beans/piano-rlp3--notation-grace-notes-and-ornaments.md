# piano-rlp3: Notation: grace notes and ornaments

**Status:** in-progress  
**Type:** feature  
**Parent:** piano-bjig  

## Context
The song format currently drops grace notes (Mikrokosmos Nos. 62 and 134: 4 notes lost), and the Soloist course Advanced I works around ornaments. Gould and MuseScore define precise geometric scaling and slash angles for acciaccaturas and placement rules for trills and turns (`docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/tlayout.cpp` (ornaments & trills) and `chordlayout.cpp` (grace notes).

Blocked by: none.

## Higher Goal
Play the exact ornamental notes composers wrote with standard professional engraving.

## Acceptance Criteria
- [ ] Syntax for acciaccatura, appoggiatura, trill, mordent, turn (written out vs symbolic). Delivered: symbolic directives `{acc:"D5"}`, `{trill}`, `{mordent}`, `{turn}`. Appoggiatura not done.
- [x] Engraving rendering (`ornament_layout.dart`):
  - [x] Grace notes rendered with notehead and stem at `graceNoteMag` 0.7 (`v450:376`, `chord.cpp:2071`); stem length 3.5 sp x 0.7 (`v450:151`).
  - [x] Acciaccatura stem slash drawn as a line, not a glyph, per `TLayout::layoutStemSlash` (`tlayout.cpp:5378`): angle 40 deg (`v450:171`), position 2 sp (`v450:170`), thickness 0.125 sp (`v450:172`). The earlier glyph choice (U+E564) was wrong; U+E560 is `graceNoteAcciaccaturaStemUp`, not the slash.
  - [x] Trill drawn as `ornamentTrill` (U+E566) at the chord origin followed by `wiggleTrill` (U+EAA4) fills, as `TrillSegment::symbolLine` (`dom/trill.cpp:73`). No generated sine path. Mordents and turns centred on the head, placed per `ChordLayout::layoutArticulations` (`chordlayout.cpp:1048`), not per `vertMargin`.
- [ ] Core parser, lint, and playback audio handling (grace notes steal small fractional time before beat). Delivered: none in core (unknown directives are ignored there). Grace notes take no time and are not played differently.
- [ ] Converter keeps them; Mikrokosmos Nos. 62 and 134 re-imported.
- [ ] Teaching lessons (scene, drill, song) for grace notes, trills, and mordents.

## Out of Scope
- Dynamics and pedal lines (`piano-boat`).
- Appoggiatura drawing and syntax (follow-up).
- Playback and time-stealing of grace notes (needs core and audio work).

## Summary of Changes
PR 4 (`feat/ornaments-trills`), rendering only:
- `app/lib/ui/staff/ornament_layout.dart`: pure geometry, each constant cited to MuseScore `file:line` or labelled a local choice (grace head and gap, stem, stem-slash line, trill symbols and baseline, mordent/turn baseline). Codepoints checked against `glyphnames.json` and the Leland cmap; advances and bboxes read from `Leland.otf`.
- `app/lib/ui/staff/song_marks_parser.dart`: parses `{trill}`, `{mordent}`, `{turn}`, `{acc:"..."}` per hand; malformed input ignored; duplicates across RH/RH2 kept once.
- `app/lib/ui/staff/staff_painter.dart`, `app/lib/practice/practice_stage.dart`: new `ornaments` and `acciaccaturas` params and wiring.
- Tests: `ornament_layout_test.dart` (geometry and paint), `song_marks_parser_test.dart` (directives, malformed, dedupe).
- Docs: `sheet-engraving.md` (matrix row, module 4), `content-format.md` (directives section).

Remaining: appoggiatura; core parser and lint for the new directives; playback of grace notes; Mikrokosmos Nos. 62 and 134 re-import; lesson content. Known visual limits: no collision check against the previous note or beams, ledger lines of grace notes approximate.
