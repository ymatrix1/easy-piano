---
# piano-fbza
title: Measure Web MIDI p95 latency with a real USB keyboard
status: completed
type: task
priority: normal
created_at: 2026-10-16T02:59:06Z
updated_at: 2026-10-16T03:38:17Z
parent: piano-bqkw
---

## Context
Split from piano-l3rl (docs/research/web-midi-spike.md). Blocked by: none.
## Higher Goal
Close D9/D2 gates.
## Acceptance Criteria
- [x] Result recorded in docs/research/web-midi-spike.md
## Out of Scope
Production code.

## Summary of Changes

Keystation Mini 32 via Web MIDI in Chrome: n=11, p50 5.8 ms, p95 7.4 ms (passes 30 ms gate). Yamaha Digital Piano delivers no MIDI to the OS; recorded in `docs/research/web-midi-spike.md`.
