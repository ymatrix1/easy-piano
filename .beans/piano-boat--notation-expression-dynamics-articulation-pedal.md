# piano-boat: Notation: expression (dynamics, articulation, pedal)

**Status:** todo  
**Type:** feature  
**Parent:** piano-bjig  

## Context
Alfred and Faber teach dynamics ($p \dots ff$, crescendo/diminuendo hairpins), staccato, legato/slurs, accents, fermata and damper pedal from the first units; our notation engine now supports ties and articulations (`engraving_decorations.dart`), but dynamics, hairpins, and damper pedal lines remain to be rendered and graded (`docs/research/method-books-sequence.md`, `docs/specs/sheet-engraving.md`).

Algorithmic reference: MuseScore `references/MuseScore/src/engraving/rendering/score/dynamicslayout.cpp` and `pedal.cpp`.

Blocked by: none.

## Higher Goal
Teach learners how to play expressively, rendering standard professional score dynamics and pedals matching MuseScore standards.

## Acceptance Criteria
- [ ] Spec & syntax: directives `{dyn: "p"}`, `{cresc}`, token annotations for staccato/accent/fermata, `{ped}`/`{ped_up}` in song JSON.
- [ ] Core parser + song model: Rust unit tests; grading rule per mark (velocity bands for MIDI, duration for staccato; mic: ignored or lenient).
- [ ] Engraving rendering (`dynamics_layout.dart`):
  - SMuFL glyphs for dynamics: $p$, $pp$, $mp$, $mf$, $f$, $ff$, $fp$, $sfz$ (U+E520–U+E540).
  - Crescendo/diminuendo hairpins (`<` and `>`) drawn below staves with proper clearance from note stems.
- [ ] Content lint rules and schema validation.
- [ ] Teaching lessons (animation scene + drill + song, strings in 5 locales) for each mark: dynamics $p/mp/mf/f/ff$, crescendo/diminuendo, staccato, legato/slur, accent, tenuto, fermata.

## Out of Scope
- Ties and repeats (covered by `piano-h90n`).
- Full damper pedal graphical bracket lines (covered by dedicated pedal bean).

## Summary of Changes
*(To be completed upon finishing)*
