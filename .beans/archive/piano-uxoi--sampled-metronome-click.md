---
# piano-uxoi
title: Sampled metronome click
status: completed
type: task
priority: normal
created_at: 2026-10-21T17:44:18Z
updated_at: 2026-10-21T17:44:18Z
---

## Context
The metronome and count-in were a square-wave beep, the most chiptune-like sound left in play-along. Split from piano-0hm5. Blocked by: none.

## Higher Goal
Realistic sound in play-along.

## Acceptance Criteria
- [x] Metronome and count-in play a recorded cross-stick (accented on beat 1), CC0, licence recorded
- [x] Beep stays as a fallback until the samples decode
- [x] Levels measured with the mix probe

## Out of Scope
Menu SFX (piano-0hm5).

## Summary of Changes
click.mp3 / click_accent.mp3 (Virtuosity Drums cross-stick vl8/vl14, snare mic + overhead, 0.25 s, 4 KB each), loaded with the piano; PianoSynth.click plays them. Probe: accent peak -6.9 dBFS, normal -12.2 dBFS (old beep -12 / -16.5 dBFS square wave).
