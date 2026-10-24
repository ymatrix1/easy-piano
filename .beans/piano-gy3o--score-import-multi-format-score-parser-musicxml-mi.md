---
# piano-gy3o
title: 'Score import: multi-format score parser (MusicXML, MIDI, ABC, LilyPond)'
status: todo
type: feature
created_at: 2026-10-24T20:13:34Z
updated_at: 2026-10-24T20:13:34Z
parent: piano-r9p5
---

## Context
Easy Piano needs the ability to import external musical scores similar to sightread.dev (supporting MusicXML, MIDI, ABC notation, and LilyPond) converting them into the internal song model for practice and engraving.

## Higher Goal
Allow users to bring any score into Easy Piano without proprietary format lock-in.

## Acceptance Criteria
- [ ] MusicXML (.xml, .musicxml, .mxl compressed) parser in core or Dart
- [ ] MIDI file (.mid, .midi) multi-track piano converter
- [ ] ABC notation parser or transpiler
- [ ] LilyPond subset parser / converter
- [ ] Pure unit tests verifying parsed notes, measures, clefs, and key signatures

## Out of Scope
- Audio recording transcription (handled in phase-3 mic import)

## Summary of Changes
*(To be completed)*
