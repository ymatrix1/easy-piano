---
# piano-9aw0
title: 'Melody model: use core difficulty evaluator for labels'
status: todo
type: task
tags:
    - difficulty
created_at: 2026-10-21T13:22:57Z
updated_at: 2026-10-21T13:22:57Z
parent: piano-7m8d
blocked_by:
    - piano-io27
---

## Context
tools/melody-model/melody_model/difficulty.level_of (branch research/melody-model-train, PR #47) is a crude heuristic. Blocked by: piano-io27, and PR #47 landing.

## Higher Goal
Training labels and generated-tune checks use the same evaluator as the course.

## Acceptance Criteria
- [ ] level_of replaced by calls to content level --jsonl (or a binding)
- [ ] Label distribution before/after reported

## Out of Scope
Retraining the model.
