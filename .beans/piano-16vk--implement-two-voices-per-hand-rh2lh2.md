---
# piano-16vk
title: Implement two voices per hand (RH2/LH2)
status: todo
type: task
created_at: 2026-10-22T19:28:39Z
updated_at: 2026-10-22T19:28:39Z
parent: piano-bjig
---

## Context

Blocked by: none. Spec: docs/specs/content-format.md#two-voices-per-hand-rh2-lh2, D34 (proposed). 69 of 147 Mikrokosmos pieces need it.

## Higher Goal

Play real piano repertoire where one hand holds a line while it plays another.

## Acceptance Criteria

- [ ] core: `RH2`/`LH2` and `s:` spacer parse; lint rules (voice sums, voice 2 needs voice 1, same-pitch overlap error); `TimedNote.voice`; tests
- [ ] Grading and wait mode treat both voices of a hand as one target stream; tests
- [ ] Staff: stem directions, voice-2 rest offset, spacers hidden, unison noteheads; widget/golden test
- [ ] Difficulty feature `two_voice_bars_per_bar`; rubric flag `two_voices`
- [ ] melody-model converter reads/writes two voices; Mikrokosmos importer accepts them; tests
- [ ] Schema and spec status updated to implemented

## Out of Scope

Three or more voices, cross-staff, meter/key changes, tuplets, importing new pieces (piano-s1iz).
