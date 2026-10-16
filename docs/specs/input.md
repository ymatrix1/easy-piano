# Input

Status: draft ([D5](../DECISIONS.md)).

| Source | Phase | Path |
|---|---|---|
| Touch keyboard | 1 | Flutter `Listener` multi-touch → NoteEvent |
| MIDI USB/BLE | 1 | Dart plugin per platform (Android `MidiManager`, iOS/macOS CoreMIDI, Web MIDI, Windows WinRT MIDI, Linux ALSA) → timestamp on audio clock → core |
| Mic monophonic | 3 | Rust YIN/MPM in audio thread |
| Mic polyphonic | research | score-informed spectral check vs expected notes; later small ONNX/TFLite model (Basic Pitch class) |

## Latency

- Calibration screen: user taps with metronome clicks; store offset per device+output.
- Budget: MIDI → frame ≤ 30 ms p95. Measured in Phase 0 spike on Pixel-class Android, iPad, Chrome desktop.

## Mic details

- Disable echo cancellation, noise suppression, AGC on web `getUserMedia`.
- Backing track bleed: duck/disable backing in mic mode until reference subtraction exists.
