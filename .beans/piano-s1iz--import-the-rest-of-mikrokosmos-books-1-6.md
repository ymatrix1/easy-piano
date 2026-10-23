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

Blocked by: none (piano-16vk done). Book 1 has 32 of 36 pieces (PR #73). Remaining blockers measured on the 147 dataset pieces (docs/research/mikrokosmos-import.md): two voices per hand 69, times 7/8 5/8 5/4 3/2 6/4 7, key/meter changes 4, tuplets 3, OMR errors (bar lengths, ties, odd key) 8. Supersedes piano-zn4c.

## Higher Goal

The whole Mikrokosmos (solo pieces) as Methods tracks.

## Acceptance Criteria

- [x] Importer makes one course per Bartók volume and takes two voices per hand
- [x] Every piece that converts today is imported (66 of 147): courses mikrokosmos-2 to -5, strings in 5 locales, restricted_in US
- [x] Lint and tests pass; web check
- Moved to piano-weqs: odd meters, meter changes, tuplets, a third voice, OCR fixes, Volume VI

## Out of Scope

Four-hand pieces (not in the dataset).

## Summary of Changes

the importer splits pieces into one course per volume (mikrokosmos-1 to -5), decodes CSV accent escapes and takes two voices per hand; 34 new pieces (Volumes II-V) with titles in five locales; melody-model tokenizer refuses second voices and spacers, difficulty ignores spacers; tests. Moved to piano-weqs: the 81 pieces that still do not convert.
