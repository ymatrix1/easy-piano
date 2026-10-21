---
# piano-pqpp
title: Research instrument samples and propose sampled band decision
status: completed
type: task
priority: normal
created_at: 2026-10-21T03:42:51Z
updated_at: 2026-10-21T13:18:51Z
---

## Context
Users say the app's backing sound is chiptune-like. Piano uses short FluidR3 samples; DRUMS/BASS/PAD/CHOIR are synthesized (D14). Blocked by: none.

## Higher Goal
Realistic instrument sound across the app with clean, openly licensed assets.

## Acceptance Criteria
- [x] docs/research/instrument-samples.md: candidates per instrument with licence, size, attribution needs; web budget
- [x] Proposed decision superseding the synth part of D14
- [x] Follow-ups recorded as beans

## Out of Scope
Code changes (piano-sound bean).

## Summary of Changes
See PR: Salamander piano, sampled FluidR3 bass/strings/choir, Virtuosity drums, expression in app/lib/audio/backing.dart, reverb/compressor/limiter mix, D22 (proposed), docs/research/instrument-samples.md with before/after measurements. Follow-ups: piano-u559, piano-v8sj, piano-ridv, piano-0hm5.
