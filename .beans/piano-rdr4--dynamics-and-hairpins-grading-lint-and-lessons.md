---
# piano-rdr4
title: 'Dynamics and hairpins: grading, lint and lessons'
status: todo
type: feature
created_at: 2026-10-24T19:07:09Z
updated_at: 2026-10-24T19:07:09Z
parent: piano-bjig
---

## Context
PR 1 of piano-boat renders dynamics (p..ff, sf, sfz) and hairpins from `{dyn}`, `{cresc}`, `{dim}`, `{end}` directives. The Rust core does not grade them yet and content lint does not validate them. Blocked by: piano-boat (rendering, in progress).

## Higher Goal
Dynamics and hairpins are part of practice feedback, not only decoration.

## Acceptance Criteria
- [ ] Core parser (`core/src/notation.rs`) knows `{dyn}`, `{cresc}`, `{dim}`, `{end}`; Rust unit tests.
- [ ] Grading rule per mark: velocity bands for MIDI, ignored or lenient for mic.
- [ ] Content lint rejects unknown `{dyn}` text and unclosed hairpins; tests in tools/content-cli.
- [ ] Teaching lessons (animation scene + drill + song, strings in 5 locales) for p/mp/mf/f/ff and crescendo/diminuendo.

## Out of Scope
- Articulation marks and damper pedal (piano-boat, later PR or bean).
- Hairpin stem clearance (piano-boat).

## Summary of Changes
*(To be completed upon finishing)*
