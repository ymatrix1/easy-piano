---
# piano-blr4
title: 'Melody model: training script and first run'
status: in-progress
type: task
tags:
    - melody-gen
created_at: 2026-10-21T02:09:23Z
updated_at: 2026-10-21T02:09:23Z
parent: piano-bovj
---

## Context
Step 4 of the browser melody model. Dataset: PR #45 (39,615 tunes, tunes.jsonl sha256 e4279fef…91e4), 50-tune gate approved by the user 2026-10-20. Design: D20, docs/specs/melody-model.md. Blocked by: none (stacked on #45).

## Higher Goal
Original practice tunes at reference-course size from our own small model, in the browser.

## Acceptance Criteria
- [ ] train.py: compound decoder transformer (sum of 4 embeddings, cascaded heads kind→pitch→dur→finger), loss after SPEC_END
- [ ] On-the-fly samples: phrase windows, spelled transposition, FIM, style dropout, plan
- [ ] Refuses to run without the gate (melody_model.gate)
- [ ] Logs loss/val loss, tokens/s, time; checkpoints in git-ignored data/
- [ ] Smoke run measured on the RTX 4070 SUPER; full run with loss curve
- [ ] Docs: params, data hash, run time, curves

## Out of Scope
ONNX export, browser demo, evaluation (steps 5–6).

## Summary of Changes
