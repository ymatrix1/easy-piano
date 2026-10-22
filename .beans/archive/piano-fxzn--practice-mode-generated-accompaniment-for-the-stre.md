---
# piano-fxzn
title: 'Practice mode: generated accompaniment for the stream'
status: completed
type: task
priority: normal
created_at: 2026-10-21T22:04:49Z
updated_at: 2026-10-21T22:27:07Z
parent: piano-c6v1
---

## Context
User asked (2026-10-21) for accompaniment generated alongside the endless practice stream. Chose rule-based accompaniment in core (option 1) over training the model on accompaniment. Blocked by: none.

## Higher Goal
Endless practice that sounds like music, not a bare line (epic piano-c6v1).

## Acceptance Criteria
- [x] core: harmonize each bar of a generated melody (C major diatonic chords) and write BASS / ACC / DRUMS parts by style and meter, pure and unit-tested
- [x] parts the learner plays are not doubled (left hand played: no BASS/ACC)
- [x] bridge call; PracticeStream adds accompaniment to every chunk
- [x] PracticeStage schedules backing for appended chunks in play-along
- [x] spec updated; checks run; verified in the web build

## Out of Scope
Model-generated accompaniment, other keys than C, per-part mixer UI.

## Summary of Changes

core/src/accompany.rs (per-bar C-major harmonization; BASS/ACC/DRUMS by style and meter; LH never doubled), bridge accompany_bars, PracticeStream adds backing to each new chunk, PracticeStage schedules backing for appended bars; endless top bar shows notes hit and streak instead of a progress bar. Verified in the release web build: chunks carry ACC+BASS+DRUMS+RH.
