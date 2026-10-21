---
# piano-bgqv
title: 'Melody model: corpus download and dataset build'
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-20T22:34:38Z
updated_at: 2026-10-21T00:32:21Z
---

## Context
Step 3 of the spec-conditioned melody model. Builds on PR #41 (converters, tokenizer; bean piano-lkg2). Corpora approved in PR #37. Parent epic piano-bovj (PR #38). Blocked by: none (stacked on #41).

## Higher Goal
Original practice tunes at reference-course size from our own small, clean model.

## Acceptance Criteria
- [x] download.py fetches approved corpora into git-ignored data/raw with a manifest (url, licence, sha256)
- [x] build.py: convert, pop/licence filter, playability filter, dedupe, plan labels, phrase cuts, transposition, split by source tune
- [x] Token shards + stats report (counts per corpus, rejects by reason, length, keys, meters)
- [x] Tests for plan labels, filters, split determinism

## Out of Scope
Training, similarity vs pop corpus beyond the existing checker, OpenScore Lieder conversion if MuseScore CLI unavailable.

## Summary of Changes
- download.py (Nottingham, PDMX, Mutopia), build.py (parallel convert, filters, dedupe, plan labels, split), labels.py, augment.py (spelled transposition, phrase windows), filters.py (PDMX flags per D21), sample.py, timed.py + local MIDI dataset registry.
- First build: 29,258 tunes kept (9,035 unflagged). Stats: docs/research/melody-dataset.md.
- 152 tests pass. Deferred: composer death-year table; 50-tune gate is bean piano-qpyc.
