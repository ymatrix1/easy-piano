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
- [x] Threshold calibrated on our songs vs each other and documented
- [x] `docs/research/melody-similarity.md`: method, open corpora and licences, implications, follow-ups

## Out of Scope
- Hooking the check into `content lint` (lint is being changed in parallel)
- n-gram index for Lakh-scale corpora, `.mxl`/kern readers
- Committing any external corpus

## Summary of Changes
- `core/src/similarity.rs` (+ `lib.rs` export): skyline melody, tokens, 6-gram overlap, Smith-Waterman alignment, `MIN_SPAN` floor of 16 tokens, `top_matches`; 6 tests.
- `tools/content-cli/src/similar.rs`: `content similar` subcommand with MIDI, ABC and MusicXML readers (3 tests); `main.rs` dispatches to it.
- Calibration: highest pair among our 40 songs 0.56 (two drills sharing a scale), highest PD-song pair 0.46; default threshold 0.6. Transposed Ode to Joy copy scores 1.00, partial ABC copy 0.85.
- `docs/research/melody-similarity.md`.
