---
# piano-weqs
title: 'Mikrokosmos: the remaining 81 pieces (meter changes, odd meters, tuplets, 3 voices, OCR fixes)'
status: todo
type: task
created_at: 2026-10-23T11:59:29Z
updated_at: 2026-10-23T11:59:29Z
parent: piano-bjig
---

## Context

Blocked by: none. 66 of 147 dataset pieces are imported (docs/research/mikrokosmos-import.md). The other 81 are skipped for: meter change inside the piece 20, wrong bar length after OCR 15, three or more voices in a hand 11, meters 3/2 6/4 5/4 5/8 7/8 8/8 10, tuplets 7, tie into another pitch 7, key change or 5+ accidentals 6, double accidentals or range 5. Volumes IV-VI are almost empty (3, 1, 0 pieces).

## Higher Goal

The whole Mikrokosmos as Methods tracks.

## Acceptance Criteria

- [ ] Decide and spec (format, converter, renderer, grading): mid-piece meter and key changes, odd meters, tuplets, a third voice
- [ ] Fix OCR errors by hand (bar lengths, ties) in a documented patch list, kept out of the dataset copy
- [ ] Import the pieces that then convert; mikrokosmos-6 course for Volume VI
- [ ] Lint, tests and web check pass

## Out of Scope

Four-hand pieces (not in the dataset).
