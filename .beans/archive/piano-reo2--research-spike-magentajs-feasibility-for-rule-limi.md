---
# piano-reo2
title: 'Research spike: Magenta.js feasibility for rule-limited melodies'
status: completed
type: task
priority: normal
tags:
    - melody-gen
created_at: 2026-10-20T22:06:07Z
updated_at: 2026-10-20T22:24:34Z
---

## Context
Practice-tune generation spike compares several methods (rules, PD variations, LLM skill, Magenta.js, hand-written) with a blind listening test. Magenta.js is TF.js-era (2018-2020), so setup risk is real; timebox half a day. Related: piano-ze9t. Blocked by: none.

## Higher Goal
Know whether a pretrained neural melody model can produce level-correct, licence-clean practice tunes for course song packs.

## Acceptance Criteria
- [x] tools/spikes/magenta/ (Node, pinned) loads basic_rnn, melody_rnn and chord_pitches_improv checkpoints
- [x] Constrained (masked) sampling for Essentials I rules; post-hoc rejection rate reported
- [x] N candidates ranked by a simple score; output in our song JSON with fingering, source generated, CC0, generator object
- [x] Code and checkpoint licenses, versions, Windows setup and time per tune recorded
- [x] docs/research/magenta-feasibility.md with results table, Implications, Follow-ups

## Out of Scope
Shipping generated songs; lint support for source generated (other session); listening test itself; training or fine-tuning models.

## Summary of Changes
- `tools/spikes/magenta/`: Node spike (pinned `@magenta/music` 1.23.1, lockfile), Tone.js stub for Node 24, `generate.js` with masked sampling, post-hoc rejection, ranking and song JSON output to `out/` (git-ignored).
- `docs/research/magenta-feasibility.md`: setup, results (masked 60/60 pass, plain 0/600), timings, licenses. Weights have no stated license, so no samples committed.
