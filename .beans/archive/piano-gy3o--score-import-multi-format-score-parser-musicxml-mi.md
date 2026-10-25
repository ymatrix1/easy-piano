---
# piano-gy3o
title: 'Score import: multi-format score parser (MusicXML, MIDI, ABC, LilyPond)'
status: completed
type: feature
created_at: 2026-10-24T20:13:34Z
updated_at: 2026-10-24T23:00:00Z
parent: piano-r9p5
---

## Context
Easy Piano needs the ability to import external musical scores similar to sightread.dev (supporting MusicXML, MIDI, ABC notation, and LilyPond) converting them into the internal song model for practice and engraving.

## Higher Goal
Allow users to bring any score into Easy Piano without proprietary format lock-in.

## Acceptance Criteria
- [x] MusicXML (.xml, .musicxml, .mxl compressed) parser in core or Dart
- [x] MIDI file (.mid, .midi) multi-track piano converter
- [x] ABC notation parser or transpiler
- [x] LilyPond subset parser / converter
- [x] Pure unit tests verifying parsed notes, measures, clefs, and key signatures

## Out of Scope
- Audio recording transcription (handled in phase-3 mic import)
- FFI bindings and conversion of `ImportedScore` into the content `Song` format (spec PR 3 `+ FFI`); tracked in a follow-up bean
- Import UI (piano-uy13)

## Summary of Changes
- New module `core/src/score_import/` with a format-independent AST `ImportedScore` (notes with start/length in quarter-note beats, hand, measures with time and key, tempo, title, composer) and `import(file_name, bytes)` dispatch by extension.
- `musicxml.rs`: partwise MusicXML and `.mxl` (zip via `zip` crate, deflate only, in memory). Handles divisions, key/time, clefs per staff, rests, chords, backup/forward, ties, `<sound tempo>`. Uses `quick-xml` 0.37.
- `midi.rs`: SMF format 0/1 reader, PPQ timing, running status, note-on velocity 0, tempo/time/key meta. Hand split: two note tracks -> RH/LH, single track at middle C. Channel 10 ignored.
- `abc.rs`: headers `X T C M L Q K V`, voices with bass clef, accidentals (reset per bar), octave marks, lengths, rests, chords, ties, tuplets, key-signature accidentals.
- `lilypond.rs`: subset with `\header`, `\score`, `\new Staff`/`PianoStaff`, `<< >>`, `\relative`, `\clef`, `\key`, `\time`, `\tempo`, `\repeat unfold`, `\times`, chords, ties, dotted values.
- Tests: 30 new unit tests in `score_import` (all green), `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` clean for `core/`.
