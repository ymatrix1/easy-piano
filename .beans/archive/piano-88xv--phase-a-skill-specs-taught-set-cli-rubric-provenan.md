---
# piano-88xv
title: 'Phase A: skill specs, taught-set CLI, rubric, provenance'
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-20T22:00:51Z
updated_at: 2026-10-20T22:17:39Z
parent: piano-bovj
---

## Context
Phase A of piano-bovj. Generators need a machine-readable target per journey node and a pure check that a candidate song stays inside what was taught.
Blocked by: none

## Higher Goal
Any generator (rules, LLM skill, Magenta) can be pointed at a node and its output checked automatically before human review.

## Acceptance Criteria
- [x] `docs/specs/skill-specs.md` and `content/skill-specs/<course>.json` for piano-basics, essentials-1..3
- [x] `content specs <dir>` prints the cumulative taught set per node, with unit tests
- [x] `core/src/rubric.rs` checks a song against taught set + node spec, unit-tested
- [x] Lint runs the rubric for songs with `spec_node`; existing songs still pass
- [x] Optional `generator` provenance; `source: generated` requires it and CC0-1.0; schema and content-format updated
- [x] Decision (proposed) on generated content
- [x] cargo test (core, content-cli) and lint pass

## Out of Scope
The compose-song skill, generating songs, similarity checks, listening page.

## Summary of Changes
- `core/src/rubric.rs`: `TaughtSet` (derive/merge/JSON), `NodeSpec`/`Pattern`, `check` with 10 unit tests.
- `Song` gains optional `generator` and `spec_node`; `source: generated` needs `generator` + CC0-1.0.
- `content specs <dir> [--out f]`; lint validates `content/skill-specs/*.json` and runs the rubric for `spec_node` songs.
- Specs for every node of piano-basics, essentials-1..3; `docs/specs/skill-specs.md`; D17 (proposed); schema and content-format updated; sync_content skips skill-specs.
