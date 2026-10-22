---
# piano-boat
title: 'Notation: expression (dynamics, articulation, pedal)'
status: todo
type: feature
created_at: 2026-10-22T19:35:14Z
updated_at: 2026-10-22T19:35:14Z
parent: piano-bjig
---

## Context
Alfred and Faber teach dynamics (p..ff, cresc/dim), staccato, legato/slurs, accents, fermata and damper pedal from the first units; our notation has none (docs/research/method-books-sequence.md, gap table). Blocked by: none.

## Higher Goal
Teach how to play, not only which notes.

## Acceptance Criteria
- [ ] Proposed decision: syntax (e.g. directives {dyn:"p"}, {cresc}, token annotations for staccato/accent/fermata, {ped}/{ped_up})
- [ ] core parser + song model, unit tests; grading rule per mark (velocity bands for dynamics on MIDI, duration for staccato; mic: ignored or lenient)
- [ ] app: marks drawn on staff, playback honours dynamics/pedal
- [ ] content-format.md, lint rules
- [ ] Lessons in Classical I / Intermediate I for dynamics, staccato, pedal

## Out of Scope
- Ties, repeats (separate bean)
