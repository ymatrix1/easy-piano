---
# piano-m4r9
title: Measure mic end-to-end latency on real devices
status: todo
type: task
created_at: 2026-10-21T16:46:29Z
updated_at: 2026-10-21T16:46:29Z
parent: piano-kxi3
---

## Context
Mic latency numbers in docs/research/mic-input.md are computed from the algorithm (~110 ms report delay), not measured. Calibration hides the offset per device, but we have no device numbers. Blocked by: none.

## Higher Goal
Evidence-backed latency budget for mic play (evidence-over-claims rule).

## Acceptance Criteria
- [ ] Key strike to NoteEvent latency measured on at least a laptop (Chrome) and a phone, same setup before/after, method documented
- [ ] Real recordings (own, acoustic + digital piano) scored with tool/mic_eval.dart

## Out of Scope
Detector changes.
