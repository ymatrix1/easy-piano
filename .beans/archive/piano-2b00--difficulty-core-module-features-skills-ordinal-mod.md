---
# piano-2b00
title: 'Difficulty: core module (features, skills, ordinal model, node_fit)'
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
Pure Rust module core/src/difficulty.rs per docs/specs/difficulty.md. Blocked by: piano-6z40.

## Higher Goal
Shared evaluator for app, content-cli and Python tools.

## Acceptance Criteria
- [x] Features per hand and per bar, 8 skill scores 0-1
- [x] Cumulative-logit level 1-10 with non-negative weights loaded from JSON
- [x] node_fit consistent with rubric by construction
- [x] Hardest bars, reasons, exceedances vs a node
- [x] Monotonicity, fixture, course-order and rubric-agreement tests

## Out of Scope
App UI.

## Summary of Changes
Done in PR feat/difficulty-evaluator: D26 (proposed), docs/specs/difficulty.md, core/src/difficulty.rs + rubric::taught_violations, core/data/difficulty-weights.json, tools/difficulty/calibrate.py, content level command and lint warning. Held-out Kendall tau 0.714, PDMX Spearman 0.577.
