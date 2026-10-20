---
# piano-9h4q
title: Melody similarity checker for generated tunes
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-20T22:04:24Z
updated_at: 2026-10-20T22:04:41Z
parent: piano-bjig
---

## Context
Generated practice tunes (agent skill, Magenta.js, rules) will fill song packs. Content is open source and clean-room, so a generated tune must not closely copy a known, especially copyrighted, melody. Used by the method-comparison spike (piano-ze9t) and later in production. Blocked by: none.

## Higher Goal
Scale course content with generated tunes without legal or ethical risk of copying.

## Acceptance Criteria
- [x] `core/src/similarity.rs`: transposition-invariant interval + rhythm-ratio tokens, interval n-gram overlap, local alignment with matched spans, top matches; unit-tested (transposed rhythm-varied copy high, unrelated tune low)
- [x] `content similar <song.json|dir> [--corpus <dir>] [--threshold x]` prints matches, exits nonzero at or above threshold
- [x] Corpus: `content/songs` plus git-ignored `references/melody-corpus/` (MIDI, ABC, MusicXML, song JSON)
- [x] Threshold calibrated with a fixture precision/recall test and documented
- [x] `docs/research/melody-similarity.md`: method, open corpora and licences, implications, follow-ups

## Out of Scope
- Hooking the check into `content lint` (lint is being changed in parallel)
- n-gram index for Lakh-scale corpora, `.mxl`/kern readers
- Committing any external corpus

## Summary of Changes
- `core/src/similarity.rs` (+ `lib.rs` export): skyline melody, interval/rhythm tokens, mod-12 interval matching, Smith-Waterman alignment; score = purity² × information × length factor (local, so contained copies and 6–8-note hooks are caught); 6-gram overlap reported. 9 unit tests.
- `core/tests/similarity_calibration.rs`: fixture precision/recall on 16 PD songs (80 positives, 248 negatives); default threshold 0.5 (recall 1.0, precision 0.92).
- `tools/content-cli/src/similar.rs`: `content similar` with MIDI (melody track pick), ABC (bar-scoped accidentals) and MusicXML readers; strict argument and input checks, exit 0/1/2. 7 tests. `main.rs` dispatches to it.
- `docs/research/melody-similarity.md`: method, calibration table, corpora (licences marked not verified), implications.
- Review fixes from PR #34: contained-copy and short-hook false negatives, CLI silent passes, ABC accidentals, non-ASCII key panic, MIDI accompaniment, per-query cloning, JSON errors counted as hits.
