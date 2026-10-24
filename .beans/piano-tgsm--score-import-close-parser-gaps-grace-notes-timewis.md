---
# piano-tgsm
title: 'Score import: close parser gaps (grace notes, timewise MusicXML, bar length)'
status: todo
type: task
created_at: 2026-10-24T20:51:42Z
updated_at: 2026-10-24T20:51:42Z
parent: piano-r9p5
---

## Context
Known gaps in docs/specs/score-import-and-page-view.md section 5.2: grace notes skipped; score-timewise rejected; measure length uses the longest voice (bug candidate); mid-piece meter changes in ABC/LilyPond ignored.
Blocked by: piano-gy3o (done).

## Higher Goal
Parsers give the bar grid and note times a printed score would show.

## Acceptance Criteria
- [ ] Measure length for an unfinished voice uses the bar's time signature, with a test
- [ ] Decide and record: score-timewise support (implement or keep rejected in spec)
- [ ] Decide and record: grace notes (time and pitch) in MusicXML/ABC/LilyPond
- [ ] Mid-piece meter changes in ABC and LilyPond: implement or keep out of scope in spec

## Out of Scope
- Fingering, dynamics and articulation import (not in ImportedScore)
