---
# piano-6z40
title: 'Difficulty: proposed decision and spec'
status: completed
type: task
priority: normal
tags:
    - difficulty
created_at: 2026-10-21T13:22:55Z
updated_at: 2026-10-21T16:27:17Z
parent: piano-7m8d
---

## Context
Evaluator design needs a decision record and spec before code. Blocked by: none.

## Higher Goal
Reviewable design for the level evaluator.

## Acceptance Criteria
- [x] Proposed decision in docs/DECISIONS.md
- [x] docs/specs/difficulty.md

## Out of Scope
Accepting the decision (user only).

## Summary of Changes
Done in PR feat/difficulty-evaluator: D24 (proposed), docs/specs/difficulty.md, core/src/difficulty.rs + rubric::taught_violations, core/data/difficulty-weights.json, tools/difficulty/calibrate.py, content level command and lint warning. Held-out Kendall tau 0.714, PDMX Spearman 0.577.
