---
# piano-c6v1
title: 'Practice mode: generate tunes in the app'
status: todo
type: epic
tags:
    - melody-gen
created_at: 2026-10-21T19:28:25Z
updated_at: 2026-10-21T19:28:25Z
---

## Context
D28 (user, 2026-10-21): the app may generate tunes at runtime in a practice mode. Model: melody-model-v1 (PR #47/#48, release D24). Blocked by: model release published; app inference path.

## Higher Goal
Endless level-fit practice for the learner's current node, on device.

## Acceptance Criteria
- [ ] Practice mode entry per node; tunes marked as generated, outside course levels and star gates
- [ ] Model download (cached, sha256-verified per D24) and on-device inference (onnxruntime-web first)
- [ ] Spec from the node's taught set; masked decoding; rubric check in core before showing
- [ ] Phone latency measured; fallback if too slow

## Out of Scope
Saving or sharing generated tunes as content. Copy check and human review in practice mode (D28: not needed).

## Summary of Changes
