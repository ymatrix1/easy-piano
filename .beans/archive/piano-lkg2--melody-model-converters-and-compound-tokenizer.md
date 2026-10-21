---
# piano-lkg2
title: 'Melody model: converters and compound tokenizer'
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-20T22:26:23Z
updated_at: 2026-10-20T22:30:29Z
---

## Context
Step 2 of the spec-conditioned browser melody model (step 1: piano-hpko, PR #37, corpora approved). Parent epic piano-bovj (PR #38, not on main yet). Blocked by: none.

## Higher Goal
Original practice tunes at reference-course scale from our own small model whose shipped weights are clean.

## Acceptance Criteria
- [x] Converters MusicXML, ABC, LilyPond (via Mutopia MIDI) to song JSON (RH/LH bars)
- [x] Compound tokenizer: one step = (kind, pitch, dur, finger); spec prefix; reserved plan and FIM tokens
- [x] Exact round-trip song JSON -> tokens -> song JSON for every file in content/songs
- [x] Converter round-trip tests (our songs exported to MusicXML/ABC/MIDI and back)

## Out of Scope
Downloading corpora, plan labels, dataset build, training.

## Summary of Changes
- tools/melody-model/: notation parser, compound tokenizer (kind/pitch/dur/finger, 360 entries), vocab.json, music21 converters (MusicXML, ABC, Mutopia MIDI for LilyPond), song_to_score writer.
- Tests (127 passing): exact token round trip for all 40 songs; MusicXML round trip exact for all 40; MIDI round trip pitch+rhythm for all 40; ABC multi-tune fixture incl. pickup and rejected triplet.
- Spec: docs/specs/melody-model.md.
