---
# piano-sctg
title: 'Research: on-device song transcription + level simplifier (D11)'
status: todo
type: task
created_at: 2026-10-16T03:47:00Z
updated_at: 2026-10-16T03:47:00Z
parent: piano-bqkw
---

## Context
User wants songs (e.g. heard on YouTube) turned into versions at their level. Proposed D11: user-supplied audio/MIDI/MusicXML only, on-device. Blocked by: none.
## Higher Goal
Learn any song at your level, legally.
## Acceptance Criteria
- [ ] Basic Pitch (or piano-specific model) runs in browser via ONNX/wasm; time per minute of audio measured
- [ ] Transcription quality on 3 PD piano recordings (note F1)
- [ ] Prototype arranger: melody extraction, transpose to C, 5-finger range, LH roots
- [ ] Findings in docs/research/song-import.md
## Out of Scope
YouTube download; server processing; UI.
