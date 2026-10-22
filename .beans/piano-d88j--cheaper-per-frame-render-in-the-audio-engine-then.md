---
# piano-d88j
title: Cheaper per-frame render in the audio engine, then retry web worklet gates
status: todo
type: task
created_at: 2026-10-21T22:51:09Z
updated_at: 2026-10-21T22:51:09Z
parent: piano-v8sj
---

## Context
D30 stage 3 (piano-0fcx) failed its web gates: the engine in an AudioWorklet costs 2-3x the render CPU of the Web Audio graph, adds key latency and first-load time (docs/research/web-audio-worklet-gates.md). Spike branch research/d30-worklet-spike has the worklet integration and probes. Blocked by: none.

## Higher Goal
One engine on every platform (D30) without a worse web experience.

## Acceptance Criteria
- [ ] Engine render cost cut (block-based compressors/reverb, skip silent buses), measured natively before/after
- [ ] Web gates rerun from the spike branch on a named device; all pass or outcome recorded in D30

## Out of Scope
Native output changes; sound changes (parity must hold).
