---
# piano-vx1w
title: 'Melody model: decide and calibrate the similarity gate'
status: todo
type: task
tags:
    - melody-gen
created_at: 2026-10-21T17:44:19Z
updated_at: 2026-10-21T17:44:19Z
parent: piano-bovj
---

## Context
The similarity check flags all 123 rubric-passing generated tunes (PR #47, releases/melody-model-v1.eval-generation.json): short low-information fragments score 1.00 against the 39,615-tune corpus. User (2026-10-21): "lets not block for now and decide later". D27 (proposed) makes the check report-only meanwhile. Blocked by: none.

## Higher Goal
Generated tunes never reproduce a recognisable copyrighted melody, without blocking ordinary music.

## Acceptance Criteria
- [ ] Known-innocent set: test-split tunes vs the training corpus; known-copy set: training tunes transposed, lightly varied, cut to 8 bars
- [ ] Match rule ignores short or low-information fragments (min notes and info), reports error rates on both sets
- [ ] Threshold chosen from both sets; recorded as a decision for the user (block, review-only, or rule)
- [ ] generate.py uses the decided rule

## Out of Scope
Retraining.

## Summary of Changes

## Note 2026-10-23

With the Soloist/Chords PD pieces (PR #76), threshold 0.5 gives 613 false positives in 5537 PD-vs-PD and generic pairs (11%); 0.8 gives 45 (0.8%) at recall 0.961. Long pieces share scale and arpeggio runs. `core/tests/similarity_calibration.rs` now calibrates on the basic courses' songs only; recalibrate on the full set here.
