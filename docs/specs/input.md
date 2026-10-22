# Input

Status: draft ([D5](../DECISIONS.md), mic: [D29](../DECISIONS.md), trained note model: [D32](../DECISIONS.md), proposed).

| Source | Phase | Path |
|---|---|---|
| Touch keyboard | 1 | Flutter `Listener` multi-touch → NoteEvent |
| MIDI USB/BLE | 1 | Dart plugin per platform (Android `MidiManager`, iOS/macOS CoreMIDI, Web MIDI, Windows WinRT MIDI, Linux ALSA) → timestamp on audio clock → core |
| Mic (web) | 3 | `getUserMedia` → AudioWorklet (`web/mic_worklet.js`) → trained note model in a Web Worker (`web/mic_model_worker.js`, onnxruntime-web, 88 keys) → NoteEvent, `Input::Mic`. Dart `NoteDetector` (onset + harmonic salience, up to 4 notes) listens until the model is ready and is the fallback |
| Mic (native) | later | same detector over the native audio engine's input, or ported to Rust `core` |
| Mic score-informed | done (web) | the expected notes pick the thresholds, for both detectors |
| Mic, "My songs" transcription | research | Basic Pitch class model (D11) |

## Latency

- Calibration screen: user taps with metronome clicks; store offset per device+output.
- Budget: MIDI → frame ≤ 30 ms p95. Measured in Phase 0 spike on Pixel-class Android, iPad, Chrome desktop.

## Mic details

- Picker: mic button in the practice top bar. Off → explanation panel (audio analysed on device, never recorded or sent; app piano muted) → browser permission → setup panel. The setup panel (game style, same for on/off) has an input-device dropdown (`enumerateDevices`, exact `deviceId`; falls back to default if the device is gone), a live level meter, the last note heard, the calibration step, and *Continue* (enabled once calibrated) plus *Cancel* or *Turn off*. Choice and device are stored per browser (`localStorage` `easy_piano.input`, `easy_piano.mic_device`); the latency offset per input device (`easy_piano.mic_offset_ms:<deviceId|default>`), so switching mics asks for a new calibration. Errors by getUserMedia `DOMException` name: NotAllowed/Security → "blocked", NotFound/Overconstrained → "no microphone" (a remembered device that vanished falls back to the default once), NotReadable/Abort → "in use by another app", anything else → "not available". The stage keeps MIDI/touch. Overlapping start/stop calls are guarded by a generation token; a start that is overtaken stops the stream it opened.
- Input gain: chunks are scaled by a slow peak follower (target 0.3, at most 30×) before detection, so quiet or distant mics still pass the onset threshold.
- `getUserMedia` with echo cancellation, noise suppression and AGC **off** (they smear attacks and pump levels).
- Feedback: in mic mode the app plays no piano for key presses and no metronome or backing after the count-in (`PracticeStage.micMode`). Pre-listen demos still play (input is ignored then).
- Timing: the worklet posts 512-frame chunks with their context frame; onsets are timed to the sample and mapped to `performance.now()`. Events carry the onset time minus the calibration offset, not the time they were reported (~100 ms later), and the session uses `Input::Mic` (early 150 ms, late 430 ms, timing bonus per `session.rs`).
- Calibration: a circle lights 8 times, 0.8 s apart (visual cue, so speakers can't trigger the mic); the student plays any key with it. Each cue (beats 3–8) takes the first onset from 200 ms before to 600 ms after it, so reaction time plus Bluetooth latency still counts; offset = median, needing ≥4 answered cues within ±150 ms of it. The ring flashes green for each note heard.
- Score-informed: the practice screen sets `micInput.expected` (wait: cursor target + next; play-along: pending targets −0.5 beat … +0.6 s). Expected notes are checked every ~20 ms on their own partials (rise, share, noise floor, tonality, neighbour tests) and may be octave/fifth doublings; unexpected notes need a broadband onset and 60 % of the strongest candidate. Calibration is optional (Continue works uncalibrated). Every note must also look like a piano string: still ringing 30 ms after the attack, pitched (sharp partials), and (expected notes) not explained by a voice an octave below; unexpected notes are re-checked 90 ms after the onset before they are reported, and none in the first 250 ms. The setup panel asks for a quiet room.
- **Note model** ([research](../research/mic-input.md#trained-model-2026-10-22-bean-piano-goe3), D32): chunks are posted from the main thread to a module Web Worker (`web/mic_model_worker.js`) that resamples to 16 kHz, computes 264 log-frequency bands per 16 ms frame (`web/mic_model_core.js`, parity-tested against `tools/mic-model/features.py`), runs the 102 KiB streaming CNN (`web/models/piano_net.onnx`, one frame plus explicit state tensors per step) with onnxruntime-web (1.30.0, single-thread wasm, shared with practice mode: staged into `web/melody/vendor/` by `tools/melody-model/web/fetch_ort.py`), and decodes onsets and releases. The raw signal is fed to the model (no gain or gate); the model sees notes about 80 ms after the attack (3 frames of look-ahead plus the window).
- Score-informed decoding: `micInput.expected` is forwarded to the worker. Expected pitches fire at a low onset threshold; other pitches need a high one, a 3-frame hold and are dropped as octave ghosts; with nothing expected a middle threshold applies. Released keys come from the frame head or a 0.6 s cap, like the DSP detector.
- Switch and fallback: `MicInput.modelEnabled` (localStorage `easy_piano.mic_model` = `off`, or `?mic=dsp` in the URL for one page load) turns the model off. The DSP detector runs until the worker reports ready, and again if the worker errors, cannot load, or falls 40 frames (0.64 s) behind real time. `MicInput.modelActive` and `modelFrameMs` expose which detector is live and the mean per-frame compute.
- Detector and fixture scores: [research/mic-input.md](../research/mic-input.md). Known limits, DSP detector: notes below C3, octave doublings (not reported), one chord note sometimes missing. Model: an octave ghost below a low note in blind mode, no evidence yet from real rooms, phone microphones or phone compute (bean piano-m4r9).
