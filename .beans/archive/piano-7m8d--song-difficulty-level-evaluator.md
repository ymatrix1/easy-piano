---
# piano-7m8d
title: Song difficulty (level) evaluator
status: completed
type: epic
priority: normal
tags:
    - difficulty
created_at: 2026-10-21T13:22:55Z
updated_at: 2026-10-21T16:27:18Z
---

## Context
Training labels for the melody model use a crude level_of heuristic. Import (D11), placement (OQ9) and generated-tune checks need a real, explainable level. Blocked by: none.

## Higher Goal
One shared, pure Rust evaluator that says how hard a song is, why, and which journey node it fits.

## Acceptance Criteria
- [x] Proposed decision + spec
- [x] core difficulty module with monotonic ordinal model
- [x] calibration script and weights
- [x] content level CLI and lint warning

## Out of Scope
App UI use, learner-data recalibration, melody-model wiring.

## Summary of Changes
Done in PR feat/difficulty-evaluator: D26 (proposed), docs/specs/difficulty.md, core/src/difficulty.rs + rubric::taught_violations, core/data/difficulty-weights.json, tools/difficulty/calibrate.py, content level command and lint warning. Held-out Kendall tau 0.714, PDMX Spearman 0.577.
