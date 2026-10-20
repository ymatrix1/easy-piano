---
# piano-hpko
title: 'Melody model: corpus research and approval'
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-20T22:16:51Z
updated_at: 2026-10-20T22:22:58Z
---

## Context
Step 1 of the spec-conditioned browser melody model. Training data must be PD/openly licensed (no pop). Blocked by: none. Parent epic: piano-bovj (Generated practice content, PR #38, not merged yet; set --parent once on main).

## Higher Goal
Original practice tunes at reference-course scale from our own small model whose shipped weights are clean.

## Acceptance Criteria
- [x] docs/research/melody-corpora.md lists candidate corpora with licence for data, redistribution and training
- [x] Recommendation (use / ask / exclude) per corpus
- [x] User approves the list before anything is downloaded

## Out of Scope
Downloading corpora, converters, tokenizer, training.

## Summary of Changes
- Added docs/research/melody-corpora.md: per-corpus licence verdicts, approved training set, approved model design (compound tokens, form plan, FIM, constrained search, later DPO).
- User approved: OpenScore Lieder, Mutopia, own songs, PDMX (filtered), Nottingham minus Ashover. Excluded: Essen, Meertens, The Session, music21 CCARH sets, IMSLP, pop sets.
