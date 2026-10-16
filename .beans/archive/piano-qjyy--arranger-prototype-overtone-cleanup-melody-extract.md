---
# piano-qjyy
title: 'Arranger prototype: overtone cleanup, melody extraction, level variants (core)'
status: completed
type: task
priority: normal
created_at: 2026-10-16T03:53:17Z
updated_at: 2026-10-16T03:59:56Z
parent: piano-kxi3
---


## Context
Follow-up from docs/research/song-import.md (D11). Blocked by: none.
## Higher Goal
My songs at your level (Phase 5).
## Acceptance Criteria
- [x] Measured result recorded in docs/research/song-import.md
## Out of Scope
UI.

## Summary of Changes

`core/src/arrange.rs` (clean, melody, level arrangements, F1) with unit tests and fixture tests on captured Basic Pitch output. Melody F1 1.00 / 1.00 / 0.98 (piano / mix / other stem) vs 0.67 / 0.48 / 0.62 raw. Tempo detection and real recordings remain (bean piano-hces + new tempo bean).
