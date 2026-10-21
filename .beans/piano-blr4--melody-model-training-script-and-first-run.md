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
- [x] train.py: compound decoder transformer (sum of 4 embeddings, cascaded heads kind→pitch→dur→finger), loss after SPEC_END
- [x] On-the-fly samples: phrase windows, spelled transposition, FIM, style dropout, plan
- [x] Refuses to run without the gate (melody_model.gate)
- [x] Logs loss/val loss, tokens/s, time; checkpoints in git-ignored data/
- [x] Smoke run measured on the RTX 4070 SUPER; full run with loss curve
- [x] Docs: params, data hash, run time, curves

## Out of Scope
ONNX export, browser demo, evaluation (steps 5–6).

## Summary of Changes
- model.py (compound GPT, RoPE, cascaded heads, 11.09M params), samples.py (windows, spelled transposition, FIM, style/level/source dropout, patterns, 30% easier variants), difficulty.py, simplify.py, train.py (gate check, token-budget batches, run dir never reused, git sha + command line in config), generate.py (masked decoding, fail-closed rubric and similarity gates), simcorpus.py, release.py (manifest + sha256 verify), curve.py.
- Run base1: 20k steps, 37 min, best val 0.875 (evidence in tools/melody-model/releases/, curve docs/models/melody-v1-loss.svg). Model card docs/models/melody-v1.md.
- content-cli: `content check`; schema: generator method melody-model.
- Decisions D24 (weights licence, proposed) and D25 (masks vs rubric, proposed) on PR #44.
