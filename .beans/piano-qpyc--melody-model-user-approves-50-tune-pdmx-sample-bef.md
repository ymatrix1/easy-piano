---
# piano-qpyc
title: 'Melody model: user approves 50-tune PDMX sample before training'
status: todo
type: task
parent: piano-bovj
tags:
    - melody-gen
created_at: 2026-10-20T22:50:42Z
updated_at: 2026-10-20T22:50:42Z
---

## Context
Review of PR #37 (user, 2026-10-20): the PDMX pop screen is metadata-based, so a human check is needed before any training run. Parent epic piano-bovj (PR #38). Blocked by: dataset build (bean piano-bgqv, branch research/melody-model-dataset).

## Higher Goal
Shipped weights are trained only on clean data.

## Acceptance Criteria
- [ ] Random 50-tune sample (fixed seed) of the filtered PDMX set exported with title, composer, licence, MuseScore id and a rendered or playable preview
- [ ] User reviews it and approves, or names tunes/patterns to tighten the screen
- [ ] Screen changes (if any) re-run and re-sampled until approved
- [ ] Approval recorded in docs/research/melody-corpora.md with date and seed

## Out of Scope
Training; non-PDMX corpora.

## Summary of Changes
