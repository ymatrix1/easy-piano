---
# piano-8v9d
title: 'Melody model v2 data: per-level filters, tuplets, core level labels, composer tokens'
status: todo
type: task
tags:
    - melody-gen
created_at: 2026-10-22T00:18:36Z
updated_at: 2026-10-22T00:18:36Z
parent: piano-bovj
---

## Context
Data work for a v2 retrain.
Roadmap: docs/research/melody-model-roadmap.md. Blocked by: piano-oial (style labels), PR #50 (difficulty evaluator).

## Higher Goal
Better generated practice tunes from our own model.

## Acceptance Criteria
- [ ] Hard tunes kept with LEVEL_4/5 instead of dropped
- [ ] Tuplets in format, converter, tokenizer
- [ ] LEVEL labels from the core difficulty evaluator (D26)
- [ ] COMPOSER tokens for PD composers and traditional styles
- [ ] Rebuild, new 50-tune gate, retrain, release melody-model-v2 (D24 process)

## Out of Scope
Two voices per hand (v3).

## Summary of Changes
