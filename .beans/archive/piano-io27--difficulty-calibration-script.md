---
# piano-io27
title: 'Difficulty: calibration script'
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
Weights must be fit from signals we have: course order, node envelopes, PDMX complexity (if present locally), simplified-vs-original pairs. Blocked by: piano-2b00.

## Higher Goal
Levels that track the course and outside difficulty labels.

## Acceptance Criteria
- [x] tools/difficulty/calibrate.py writes core weights JSON
- [x] Reports Kendall tau on held-out course songs and PDMX agreement

## Out of Scope
Learner-data recalibration.

## Summary of Changes
Done in PR feat/difficulty-evaluator: D23 (proposed), docs/specs/difficulty.md, core/src/difficulty.rs + rubric::taught_violations, core/data/difficulty-weights.json, tools/difficulty/calibrate.py, content level command and lint warning. Held-out Kendall tau 0.714, PDMX Spearman 0.577.
