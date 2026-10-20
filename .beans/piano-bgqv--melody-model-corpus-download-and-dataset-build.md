---
# piano-bgqv
title: 'Melody model: corpus download and dataset build'
status: in-progress
type: task
tags:
    - melody-gen
created_at: 2026-10-20T22:34:38Z
updated_at: 2026-10-20T22:34:38Z
---

## Context
Step 3 of the spec-conditioned melody model. Builds on PR #41 (converters, tokenizer; bean piano-lkg2). Corpora approved in PR #37. Parent epic piano-bovj (PR #38). Blocked by: none (stacked on #41).

## Higher Goal
Original practice tunes at reference-course size from our own small, clean model.

## Acceptance Criteria
- [ ] download.py fetches approved corpora into git-ignored data/raw with a manifest (url, licence, sha256)
- [ ] build.py: convert, pop/licence filter, playability filter, dedupe, plan labels, phrase cuts, transposition, split by source tune
- [ ] Token shards + stats report (counts per corpus, rejects by reason, length, keys, meters)
- [ ] Tests for plan labels, filters, split determinism

## Out of Scope
Training, similarity vs pop corpus beyond the existing checker, OpenScore Lieder conversion if MuseScore CLI unavailable.

## Summary of Changes
