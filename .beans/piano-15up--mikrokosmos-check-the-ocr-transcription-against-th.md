---
# piano-15up
title: 'Mikrokosmos: check the OCR transcription against the printed pages'
status: todo
type: task
created_at: 2026-10-23T12:25:38Z
updated_at: 2026-10-23T12:25:38Z
parent: piano-bjig
---

## Context

Blocked by: none. The MusicXML of Mikrokosmos-difficulty is OCR plus manual fixes. Notes were counted against the XML for all 66 imported pieces, but only Nos. 31 and 56 were compared with the printed page (dataset pdfs/<n>.pdf); a wrong pitch that still fills its bar passes every test.

## Higher Goal

Lessons whose notes are right.

## Acceptance Criteria

- [ ] Each of the 66 imported pieces compared with its printed page (pitch, rhythm, rests, accidentals, hands); list of pieces checked kept in docs/research/mikrokosmos-import.md
- [ ] Every difference fixed in the importer as a documented patch list (not by editing the dataset copy), pieces re-imported
- [ ] Optional: a script that renders each song and the page side by side to speed up the review

## Out of Scope

Marks the XML does not carry (piano-boat); the 81 skipped pieces (piano-weqs).
