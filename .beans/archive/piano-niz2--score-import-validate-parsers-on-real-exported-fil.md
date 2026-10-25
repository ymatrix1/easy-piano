---
# piano-niz2
title: 'Score import: validate parsers on real exported files'
status: completed
type: task
priority: normal
created_at: 2026-10-24T20:51:42Z
updated_at: 2026-10-25T22:33:40Z
parent: piano-r9p5
---

## Context
Parsers in core/src/score_import (piano-gy3o) are tested with inline fixtures only. Nothing from MuseScore/OpenScore (.mxl), Mutopia (.ly), PDMX or DAW MIDI exports has been parsed. See docs/specs/score-import-and-page-view.md section 5.
Blocked by: none (piano-gy3o done).

## Higher Goal
Imported scores match what the source shows, on real files, before the import UI relies on them.

## Acceptance Criteria
- [x] Fixtures from at least 3 sources (MuseScore .mxl, Mutopia .ly, one DAW MIDI) committed with license fields (`core/tests/fixtures/score_import/SOURCES.md`). The MIDI is a CC0 sequencer file; its DAW origin is not documented, so the "DAW" label is unconfirmed.
- [x] Expected notes, measures and hands checked per fixture (`core/tests/score_import_real.rs`: LilyPond vs its own MIDI export, MusicXML piano part counted by an independent script, MIDI vs mido)
- [x] Failures found are fixed or recorded as new limitations in spec section 5.2 (fixed: piano part selection in MusicXML, `\transpose`, music variables, `\context`, cautionary accidentals in LilyPond)

## Out of Scope
- Song conversion and FFI (piano-t6rt)
- Import UI (piano-uy13)
- PDMX files (not fetched; no license check yet)

## Summary of Changes
- Fixtures: Mutopia BWV 846 Prelude 1 (`.ly` + LilyPond `.mid`, PD), OpenScore "Just for Today" (`.mxl`, MuseScore 4.5.2, CC0), Commons "Piano Boogie left hand pattern" (`.mid`, CC0).
- `core/src/score_import/lilypond.rs`: music variables, `\transpose`, `\context`, `!`/`?` accidentals. Unit tests.
- `core/src/score_import/musicxml.rs`: when a part has two or more staves, only those parts are read (a sung line is dropped). Unit test.
- `core/tests/score_import_real.rs`: 4 integration tests on the fixtures.
- Spec 5.2 and 5.3 updated.
