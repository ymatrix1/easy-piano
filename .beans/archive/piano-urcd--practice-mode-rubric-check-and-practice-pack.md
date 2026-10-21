---
# piano-urcd
title: 'Practice mode: rubric check and practice pack'
status: completed
type: task
priority: normal
created_at: 2026-10-21T19:32:15Z
updated_at: 2026-10-21T20:23:29Z
parent: piano-c6v1
---


## Context
D28 (accepted): practice tunes are generated on device and must pass the rubric for the node's taught set. The taught set is computed by content-cli (taught_walk); the app has no copy. Blocked by: none.

## Higher Goal
Endless level-fit practice per node (epic piano-c6v1).

## Acceptance Criteria
- [x] core: TaughtSet serde round-trip and check_generated(song_json, node_json) that rejects non-generated songs
- [x] content-cli: practice-pack subcommand writes per-node taught set, spec and generation spec
- [x] bridge: check_generated exposed to Dart
- [x] sync_content.py writes assets/content/practice.json
- [x] tests in core and content-cli

## Out of Scope
Model inference, UI.

## Summary of Changes

core: TaughtSet/Pattern/NodeSpec serde, PracticeNode, rubric::check_generated (fails closed, requires source generated + melody-model). content-cli: practice-pack (practice.rs, level_for/gen_spec ported from generate.py). Bridge: check_generated. sync_content.py writes practice.json and copies the manifest and melody.js.
