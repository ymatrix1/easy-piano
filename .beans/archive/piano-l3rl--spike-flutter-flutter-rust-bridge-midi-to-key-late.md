---
# piano-l3rl
title: 'Spike: Flutter + flutter_rust_bridge MIDI-to-key latency on Android, iOS, web'
status: completed
type: task
priority: normal
created_at: 2026-10-16T02:43:04Z
updated_at: 2026-10-16T02:59:06Z
parent: piano-bqkw
---

## Context
See docs/ROADMAP.md Phase 0 and docs/specs/curriculum.md. Blocked by: none.
## Higher Goal
De-risk Phase 1.
## Acceptance Criteria
- [x] Result recorded in docs/ (research file, spec or decision)
## Out of Scope
Production code.

## Summary of Changes

- Flutter web app scaffold in `app/` with Web MIDI input (`app/lib/input/midi_input_web.dart`), touch keyboard, shared `KeyGeometry`, live latency stats.
- First load ~2.5 MB gzipped (passes D9 gate). Results: `docs/research/web-midi-spike.md`.
- Not done, split into new beans: real-keyboard MIDI latency, flutter_rust_bridge wasm, mobile smoke builds.
