---
# piano-ze9t
title: 'Research spike: constrained melody generation for drills'
status: todo
type: task
created_at: 2026-10-16T18:13:37Z
updated_at: 2026-10-16T18:13:37Z
---

## Context
Drills and extra practice use hand-written melodies; we want more, nicer ones per level. Blocked by: none. Research doc: docs/research/melody-generation.md. Not scheduled; documented for later.

## Higher Goal
Endless, musical, level-correct practice material (CC0, our own) without hand-writing each exercise.

## Acceptance Criteria
- [ ] Prototype `content generate --level N --seed S` in tools/content-cli emitting our song JSON
- [ ] Hard constraints from the level rubric (notes, range, fingers, rhythms, max leap, accidentals); output passes `content lint`
- [ ] Musicality score (chord tones on strong beats, motif repetition, stepwise motion, arch contour, cadence)
- [ ] 10 generated samples per level 1-3 reviewed by ear; findings appended to the research doc
- [ ] Proposed decision (generator role, LLM yes/no) in docs/DECISIONS.md

## Out of Scope
Shipping generated songs in the official course; neural models with unclear weight licenses.
