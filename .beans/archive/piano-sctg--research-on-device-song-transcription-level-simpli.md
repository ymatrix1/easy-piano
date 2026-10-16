---
# piano-sctg
title: 'Research: on-device song transcription + level simplifier (D11)'
status: completed
type: task
priority: normal
created_at: 2026-10-16T03:47:00Z
updated_at: 2026-10-16T03:53:17Z
parent: piano-bqkw
---



## Context
User wants songs (e.g. heard on YouTube) turned into versions at their level. Proposed D11: user-supplied audio/MIDI/MusicXML only, on-device. Blocked by: none.
## Higher Goal
Learn any song at your level, legally.
## Acceptance Criteria
- [x] Basic Pitch runs in browser (TF.js); 20 s audio in 1.0 s warm
- [ ] Transcription quality on 3 PD piano recordings (note F1): moved to follow-up bean; synthetic set measured instead
- [x] Stem separation on web: 0.37x realtime, 181 MB model (native not measured)
- [x] Stems play back individually in the page (mute-any-stem feasible)
- [ ] Prototype arranger (moved to follow-up bean): melody extraction, transpose to C, 5-finger range, LH roots
- [x] Findings in docs/research/song-import.md
## Out of Scope
YouTube download; server processing; UI.

## Summary of Changes

Browser spike in `tools/spikes/song-import/`: Demucs (demucs-web, ONNX) separates 20 s in 7.5 s; Basic Pitch transcribes with R=1.00, P 0.32 (mix) to 0.45 (other stem). Findings in `docs/research/song-import.md`. Real recordings and arranger split into follow-up beans.
