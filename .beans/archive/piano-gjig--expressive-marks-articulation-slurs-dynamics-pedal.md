---
# piano-gjig
title: 'Expressive marks: articulation, slurs, dynamics, pedal, fermata, text, grace notes'
status: scrapped
type: task
priority: normal
created_at: 2026-10-23T12:20:52Z
updated_at: 2026-10-23T12:25:37Z
parent: piano-bjig
---

## Context

Blocked by: none. The imported Mikrokosmos pieces carry notes only. Measured in the 66 imported MusicXML files (docs/research/mikrokosmos-import.md#what-the-source-has-and-the-lessons-drop): slurs 1630 marks in 57 pieces, staccato 187 in 14, accents 37 in 4, tenuto 15 in 3, hairpins 119 in 20, fermata 8 in 5, pedal 52 in 3, grace notes 4 in 2. The dataset has no dynamic letters and no fingering (the printed pages do).

## Higher Goal

Lessons that teach phrasing and touch, not only pitch and rhythm; both method books taught these from the first pages.

## Acceptance Criteria

- [ ] Spec (decision, proposed): song format fields for each mark, written so grading ignores them; renderer rules (SMuFL glyphs already bundled)
- [ ] Part 1: articulation (staccato, accent, tenuto) and fermata: parse, render, converter keeps them
- [ ] Part 2: slurs
- [ ] Part 3: dynamics letters and hairpins (source for the letters: our own transcription from the printed pages, decided by the user)
- [ ] Part 4: pedal, tempo/character words, grace notes
- [ ] Re-import Mikrokosmos with the marks; lint, tests, web check

## Out of Scope

Playback of expression (velocity, pedal in the synth) unless the spec asks; ornaments the sources do not contain.

## Reasons for Scrapping

Duplicates piano-boat (expression marks) and piano-h90n (ties, repeats, key and meter changes), written in PR #76. The Mikrokosmos measurements stay in docs/research/mikrokosmos-import.md and feed those beans.
