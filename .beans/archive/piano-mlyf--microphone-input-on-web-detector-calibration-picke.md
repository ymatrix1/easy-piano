---
# piano-mlyf
title: Microphone input on web (detector, calibration, picker)
status: completed
type: task
priority: normal
created_at: 2026-10-20T21:37:21Z
updated_at: 2026-10-20T22:28:38Z
parent: piano-kxi3
---


## Context
Students with an acoustic or non-MIDI digital piano cannot play today. Core already has Input::Mic (early 150 ms, late 430 ms, timing bonus). Blocked by: none.

## Higher Goal
Make the course playable without a MIDI cable (Phase 3: Mic and library).

## Acceptance Criteria
- [x] Web capture via getUserMedia + AudioWorklet
- [x] Onset + chord-capable pitch detector emitting NoteEvent
- [x] Mic option in practice top bar, permission errors shown
- [x] Calibration step stores latency offset
- [x] App piano sound muted in mic mode
- [x] Fixture set + precision/recall/F1 + latency in docs/research/mic-input.md
- [x] docs/specs/input.md updated, proposed decision recorded

## Out of Scope
Native (Android/iOS/desktop) mic capture; ML models (Basic Pitch); backing-track subtraction.

## Summary of Changes
- `app/lib/input/mic/`: `NoteDetector` (spectral-flux onsets + harmonic-salience chord picking, pure Dart), `MicInput` (web: getUserMedia without EC/NS/AGC → `web/mic_worklet.js` → detector → NoteEvent; stub elsewhere).
- Practice: mic button in top bar, explanation dialog, permission errors, visual-cue calibration (`mic_calibration.dart`), session runs with `Input::Mic`, app piano/metronome/backing muted in mic mode. Strings in 5 languages.
- Fixtures: `tools/mic_fixtures.py` (138 clips from the app's MIT samples, git-ignored) and `app/tool/mic_eval.dart`. F1 0.891 overall (clean 0.951, room 0.872, noisy 0.853); onset p95 ≤ 16 ms; report delay ~100 ms.
- Docs: `docs/research/mic-input.md`, `docs/specs/input.md`, D17 (proposed), ROADMAP.
- Web demo: Find middle C completed 4/4 through the mic pipeline with a stubbed MediaStream (no physical piano).

