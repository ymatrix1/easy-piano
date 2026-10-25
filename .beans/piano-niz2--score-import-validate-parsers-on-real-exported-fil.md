---
# piano-niz2
title: 'Score import: validate parsers on real exported files'
status: todo
type: task
created_at: 2026-10-24T20:51:42Z
updated_at: 2026-10-24T20:51:42Z
parent: piano-r9p5
---

## Context
Parsers in core/src/score_import (piano-gy3o) are tested with inline fixtures only. Nothing from MuseScore/OpenScore (.mxl), Mutopia (.ly), PDMX or DAW MIDI exports has been parsed. See docs/specs/score-import-and-page-view.md section 5.
Blocked by: none (piano-gy3o done).

## Higher Goal
Imported scores match what the source shows, on real files, before the import UI relies on them.

## Acceptance Criteria
- [ ] Fixtures from at least 3 sources (MuseScore .mxl, Mutopia .ly, one DAW MIDI) committed with license fields
- [ ] Expected notes, measures and hands checked per fixture (test or documented diff)
- [ ] Failures found are fixed or recorded as new limitations in spec section 5.2

## Out of Scope
- Song conversion and FFI (piano-t6rt)
- Import UI (piano-uy13)
