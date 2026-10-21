---
# piano-oial
title: 'Melody model: label untagged tunes with a style classifier'
status: todo
type: task
tags:
    - melody-gen
created_at: 2026-10-21T02:08:38Z
updated_at: 2026-10-21T02:08:38Z
parent: piano-bovj
---

## Context
12,999 PDMX tunes have no style label (no genre tag, no keyword match): mostly untagged folk tunes and hymns. They train the unconditioned path but cannot be requested by style. User (2026-10-20): train first, come back to this. Blocked by: first training run (step 4).

## Higher Goal
Style control (STYLE_* tokens) that covers the whole dataset.

## Acceptance Criteria
- [ ] Try CLaMP 2 zero-shot (style names as text prompts) on ABC/MIDI exports; record licence of code and weights
- [ ] Accuracy on ~2k held-out tagged tunes: per-style precision/recall
- [ ] Fallback if setup fails: own classifier trained on the 26k tagged tunes
- [ ] Better keyword rules (composer names, more title words) as a cheap first pass
- [ ] Guessed labels stored separately (styles_guessed, tool, version, confidence), threshold chosen from the accuracy test
- [ ] Rebuild + retrain decision

## Out of Scope
Shipping the classifier.

## Summary of Changes
