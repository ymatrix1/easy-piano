---
# piano-urcd
title: 'Practice mode: rubric check and practice pack'
status: in-progress
type: task
created_at: 2026-10-21T19:32:15Z
updated_at: 2026-10-21T19:32:15Z
parent: piano-c6v1
---

## Context
D28 (accepted): practice tunes are generated on device and must pass the rubric for the node's taught set. The taught set is computed by content-cli (taught_walk); the app has no copy. Blocked by: none.

## Higher Goal
Endless level-fit practice per node (epic piano-c6v1).

## Acceptance Criteria
- [ ] core: TaughtSet serde round-trip and check_generated(song_json, node_json) that rejects non-generated songs
- [ ] content-cli: practice-pack subcommand writes per-node taught set, spec and generation spec
- [ ] bridge: check_generated exposed to Dart
- [ ] sync_content.py writes assets/content/practice.json
- [ ] tests in core and content-cli

## Out of Scope
Model inference, UI.
