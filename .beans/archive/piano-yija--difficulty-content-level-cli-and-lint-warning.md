---
# piano-yija
title: 'Difficulty: content level CLI and lint warning'
status: completed
type: task
priority: normal
tags:
    - difficulty
created_at: 2026-10-21T13:22:56Z
updated_at: 2026-10-21T16:27:17Z
parent: piano-7m8d
---

## Context
Authors need the evaluator from the CLI. Blocked by: piano-2b00.

## Higher Goal
Catch course songs whose level is far from their node.

## Acceptance Criteria
- [x] content level <content_dir> <song.json>... prints JSON
- [x] lint warns (not errors) when a course song's level is far from its node

## Out of Scope
Making it an error.

## Summary of Changes
Done in PR feat/difficulty-evaluator: D24 (proposed), docs/specs/difficulty.md, core/src/difficulty.rs + rubric::taught_violations, core/data/difficulty-weights.json, tools/difficulty/calibrate.py, content level command and lint warning. Held-out Kendall tau 0.714, PDMX Spearman 0.577.
