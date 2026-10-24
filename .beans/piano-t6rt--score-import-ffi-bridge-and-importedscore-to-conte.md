---
# piano-t6rt
title: 'Score import: FFI bridge and ImportedScore to content Song conversion'
status: todo
type: task
created_at: 2026-10-24T20:47:24Z
updated_at: 2026-10-24T20:47:24Z
parent: piano-r9p5
---

## Context
Follow-up of piano-gy3o. Parsers for MusicXML, MIDI, ABC and LilyPond exist in core/src/score_import and return ImportedScore. Missing: flutter_rust_bridge API in app/rust/src/api/ and conversion of ImportedScore into the content Song format (bars per hand, docs/specs/content-format.md).
Blocked by: piano-gy3o (done).

## Higher Goal
Imported scores can be played and engraved in the app.

## Acceptance Criteria
- [ ] Conversion ImportedScore -> content Song with unit tests
- [ ] FFI function import_score(file_name, bytes) exposed via flutter_rust_bridge
- [ ] flutter_rust_bridge_codegen generate run and committed

## Out of Scope
- Import UI (piano-uy13)
