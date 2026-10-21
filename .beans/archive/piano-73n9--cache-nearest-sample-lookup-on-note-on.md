---
# piano-73n9
title: Cache nearest-sample lookup on note-on
status: completed
type: task
created_at: 2026-10-20T22:17:03Z
updated_at: 2026-10-20T22:17:03Z
---

## Context
Key-press path in the web synth rescanned all decoded samples per note and created the piano bus lazily. Blocked by: none.

## Higher Goal
Keep note-on to sound latency minimal (D1: p95 under 30 ms).

## Acceptance Criteria
- [x] Nearest-sample lookup cached per pitch, cleared when samples load
- [x] Piano bus created with the audio context
- [x] flutter analyze clean on lib/audio
- [ ] Measured latency gain (not measured: needs MIDI keyboard)

## Out of Scope
latencyHint 0: measured identical baseLatency 10 ms / outputLatency 40 ms (Chrome 152, Windows 11), reverted.

## Summary of Changes
Cache in piano_synth_web.dart; bus created in _context().
