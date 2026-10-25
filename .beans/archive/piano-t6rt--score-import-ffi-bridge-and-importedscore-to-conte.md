---
# piano-t6rt
title: 'Score import: FFI bridge and ImportedScore to content Song conversion'
status: completed
type: task
priority: normal
created_at: 2026-10-24T20:47:24Z
updated_at: 2026-10-25T22:11:40Z
parent: piano-r9p5
---

## Context
Follow-up of piano-gy3o. Parsers for MusicXML, MIDI, ABC and LilyPond exist in core/src/score_import and return ImportedScore. Missing: flutter_rust_bridge API in app/rust/src/api/ and conversion of ImportedScore into the content Song format (bars per hand, docs/specs/content-format.md).
Blocked by: piano-gy3o (done).

## Higher Goal
Imported scores can be played and engraved in the app.

## Acceptance Criteria
- [x] Conversion ImportedScore -> content Song with unit tests
- [x] FFI function import_score(file_name, bytes) exposed via flutter_rust_bridge
- [x] flutter_rust_bridge_codegen generate run and committed

## Out of Scope
- Import UI (piano-uy13)

## Summary of Changes
- core/src/score_import/song.rs: ImportedScore to content song JSON (chords, two voices per hand, ties at bar lines, exact tuplet durations, key and tempo mapping, custom source). Unit tests.
- pp/rust/src/api/score_import.rs: FFI import_score(file_name, data); generated bridge files (rb_generated*, pp/lib/src/rust/api/score_import.dart).
- pp/rust/Cargo.lock: lock refreshed for core deps (quick-xml, zip).
- Spec docs/specs/score-import-and-page-view.md section 5.5 (limits); D40 proposed in docs/DECISIONS.md.
- Tests: core 162 unit tests pass; app/rust 2 tests pass; clippy -D warnings clean.
- Not verified: wasm build of the bridge; real-file import (piano-niz2).
