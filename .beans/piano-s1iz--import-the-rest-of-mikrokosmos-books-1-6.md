---
# piano-s1iz
title: Import the rest of Mikrokosmos (Books 1-6)
status: todo
type: task
created_at: 2026-10-22T19:28:39Z
updated_at: 2026-10-22T19:28:39Z
parent: piano-bjig
blocked_by:
    - piano-16vk
---

## Context

Blocked by: piano-16vk (two voices per hand). Book 1 has 32 of 36 pieces (PR #73). Remaining blockers measured on the 147 dataset pieces (docs/research/mikrokosmos-import.md): two voices per hand 69, times 7/8 5/8 5/4 3/2 6/4 7, key/meter changes 4, tuplets 3, OMR errors (bar lengths, ties, odd key) 8. Supersedes piano-zn4c.

## Higher Goal

The whole Mikrokosmos (solo pieces) as Methods tracks.

## Acceptance Criteria

- [ ] Converter accepts 7/8, 5/8, 5/4, 3/2, 6/4 (app renders them)
- [ ] Decide meter/key change and tuplet support (spec or approved simplification)
- [ ] OMR errors fixed by hand with notes in the research doc
- [ ] Courses mikrokosmos-2..6 (one per book) in the methods section, strings in 5 locales, restricted_in US
- [ ] Lint, tests, web check pass

## Out of Scope

Four-hand pieces (not in the dataset).
