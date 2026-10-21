---
# piano-0hm5
title: Sampled menu SFX
status: completed
type: task
priority: normal
created_at: 2026-10-21T13:18:09Z
updated_at: 2026-10-21T17:49:44Z
---

## Context
Menu SFX are still oscillators (the metronome click moved to a sample in piano-uxoi) and sound chiptune-like next to the sampled band. Found in piano-k1d3 (D22). Blocked by: none.

## Higher Goal
Realistic, properly credited sound on every platform.

## Acceptance Criteria
- [x] Menu SFX use openly licensed samples (the Salamander piano already shipped), licence recorded

## Out of Scope
Anything else from D22.

## Summary of Changes
Musical menu cues play short phrases on the sampled Salamander piano via a new sfx bus; hover/open/close are noise only (no oscillator beeps); synth fallback until piano decodes. No new assets.
