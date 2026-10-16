---
# piano-s5pb
title: Notation parser, JSON Schema and content lint
status: completed
type: task
priority: normal
created_at: 2026-10-16T04:51:29Z
updated_at: 2026-10-16T04:56:59Z
parent: piano-eeut
---


## Context
Phase 1 (docs/ROADMAP.md). Spec: docs/specs/content-format.md. Blocked by: none.
## Higher Goal
First playable web version (D9).
## Acceptance Criteria
- [x] Delivered and verified, ROADMAP box ticked
## Out of Scope
Other Phase 1 items.

## Summary of Changes

`core/src/notation.rs` (tokens, rational durations, chords, fingering, directives) and `core/src/song.rs` (model, validation, beat timeline), 10 new unit tests; `tools/content-cli` lint with cross-reference and string checks; `content/schema/song.schema.json`. Verified: lint ok on content, exit 1 with 7 errors on a deliberately broken copy.
