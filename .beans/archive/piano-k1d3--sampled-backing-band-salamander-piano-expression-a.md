---
# piano-k1d3
title: Sampled backing band, Salamander piano, expression and mix
status: completed
type: feature
priority: normal
created_at: 2026-10-21T03:42:51Z
updated_at: 2026-10-21T13:18:51Z
---

## Context
D14 synth drums/bass/pad/choir and truncated FluidR3 piano notes sound chiptune-like. Blocked by: none (decision is proposed alongside).

## Higher Goal
Play-along and free play sound like real instruments on web without breaking native or grading.

## Acceptance Criteria
- [x] DRUMS, BASS, PAD, CHOIR play samples; piano uses Salamander Grand with velocity brightness
- [x] Expression on app-played parts: beat/phrase velocity, small humanized timing on backing only, releases, pedalled chords
- [x] Mix: generated-IR reverb send, gentle compressor/limiter; default mix rebalanced; setPartLevel kept
- [x] content-format gain table updated; asset README/licence files
- [x] Before/after on Ode to Joy play-along: per-part RMS, peak, asset size, first-load time
- [x] flutter analyze/test pass; web build checked in browser

## Out of Scope
Native audio engine (stub stays silent); listening-test tool alignment.

## Summary of Changes
See PR: Salamander piano, sampled FluidR3 bass/strings/choir, Virtuosity drums, expression in app/lib/audio/backing.dart, reverb/compressor/limiter mix, D22 (proposed), docs/research/instrument-samples.md with before/after measurements. Follow-ups: piano-u559, piano-v8sj, piano-ridv, piano-0hm5.
