---
# piano-d8yj
title: 'Methods: Mikrokosmos Book 1 as a guided track'
status: in-progress
type: task
priority: normal
created_at: 2026-10-22T18:53:41Z
updated_at: 2026-10-22T19:14:00Z
parent: piano-bjig
---

## Context

Blocked by: none. Follows the methods spike (piano-b9b2, docs/research/piano-method-library-spike.md). The user chose Bartók's Mikrokosmos as the first method and approved using the MusicXML of the Mikrokosmos-difficulty dataset (PRamoneda/Mikrokosmos-difficulty, OMR + manual correction, no licence file) and publishing it (D33, proposed).

## Higher Goal

A Methods area with rights-reviewed, progressive repertoire next to the main course.

## Acceptance Criteria

- [ ] Reproducible import script from the dataset MusicXML to song JSON (key signature kept as written, tempo from the metronome mark, multi-voice bars refused)
- [ ] Book 1 pieces that the format can hold imported as songs with provenance and a US restriction until 2036-01-01
- [ ] Methods section and a Mikrokosmos I course with one node and level per piece, strings in en and pt-BR
- [ ] Optional `restricted_in` song field: schema, lint, content-format spec
- [ ] D33 (proposed) records the licence position and the US term
- [ ] content lint, melody-model tests and app tests pass

## Out of Scope

Books 2-6; pieces the format cannot hold yet (meter changes, triplets, 3/2 and 6/4); in-app region gating; teaching prompts per piece; fingering (the dataset has none).
