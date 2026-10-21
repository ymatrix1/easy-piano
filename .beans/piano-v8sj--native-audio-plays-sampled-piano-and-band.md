---
# piano-v8sj
title: One Rust audio engine for all platforms (D30)
status: todo
type: epic
created_at: 2026-10-21T13:18:09Z
updated_at: 2026-10-21T13:18:09Z
---

## Context
Android/iOS/desktop are silent (`piano_synth_stub.dart`); D22 sound lives only in the Web Audio graph. D30 (proposed): one Rust `audio/` engine for every platform, web via AudioWorklet, so web and phones sound identical. Blocked by: none.

## Higher Goal
Same realistic sound on every platform, one audio clock (rule 7), memory that fits phones.

## Acceptance Criteria
- [ ] Stage 1: offline engine + CI parity test (child bean)
- [ ] Stage 2: native output with measured latency (child bean)
- [ ] Stage 3: web AudioWorklet replaces the Web Audio graph (child bean)
- [ ] Blind A/B listen web vs native by the user
- [ ] D30 accepted or revised by the user

## Out of Scope
Menu SFX (stay synthesized), mic input, new instruments.
