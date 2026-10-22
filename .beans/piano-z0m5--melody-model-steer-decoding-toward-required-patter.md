---
# piano-z0m5
title: 'Melody model: steer decoding toward required patterns'
status: todo
type: task
tags:
    - melody-gen
created_at: 2026-10-22T00:18:34Z
updated_at: 2026-10-22T00:18:34Z
parent: piano-bovj
---

## Context
Rubric failures in v1 (23%) are unmet required patterns.
Roadmap: docs/research/melody-model-roadmap.md. Blocked by: none.

## Higher Goal
Better generated practice tunes from our own model.

## Acceptance Criteria
- [ ] Near the end of a tune, boost or force a missing required pitch, accidental, rhythm, rest or interval
- [ ] Rubric pass rate measured before/after on the same 10 nodes

## Out of Scope
Retraining.

## Summary of Changes
