---
# piano-0h6i
title: 'Android: native MIDI keyboard and microphone input'
status: in-progress
type: task
created_at: 2026-10-21T23:38:22Z
updated_at: 2026-10-21T23:38:22Z
---
## Context

Native Android builds used the stub inputs, so Free Play and lessons showed "Web MIDI is not available in this browser." and "Microphone input is not available in this browser." Blocked by: none (Android launch fixes live on `fix/android-arm64-launch`, not needed to review the code).

## Higher Goal

Phase 2: the app is usable on a phone with a MIDI keyboard or the microphone, like the web build ([D32](../docs/DECISIONS.md)).

## Acceptance Criteria

- [ ] `MidiInput` on Android uses `android.media.midi` (USB + BLE devices already connected to the system), hot-plug included
- [ ] `MicInput` on Android captures with `AudioRecord`, asks for `RECORD_AUDIO` at runtime, feeds the existing Dart `NoteDetector`
- [ ] Manifest declares `RECORD_AUDIO` and optional `android.software.midi` / microphone features
- [ ] Native error texts never say "browser" (new strings in all locales)
- [ ] Web unchanged; `flutter analyze` and `flutter test` pass
- [ ] USB MIDI keyboard and mic drive Free Play and a lesson on a device (logcat/screenshot proof)
- [ ] `docs/specs/input.md`, `docs/ARCHITECTURE.md` updated; D32 recorded as proposed

## Out of Scope

iOS/desktop input; BLE scanning and pairing inside the app; Oboe low-latency capture (follow-up if measured latency needs it); moving detection into Rust.
