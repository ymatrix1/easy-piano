# Web audio engine in an AudioWorklet: stage 3 gates (D30)

Checked: 2026-10-21

Sources: our own measurements in the browser (setup below); `audio/` engine and its parity test; spike code on branch `research/d30-worklet-spike` (commit `02fd74b`, not merged).

Question: can web replace the D22 Web Audio graph with the Rust engine (`audio/`, D30) compiled to wasm and run in an AudioWorklet, without worse key latency, audio-thread CPU or first-load time, and with the same sound?

## Setup

| Item | Value |
|---|---|
| Device | Desktop PC, AMD Ryzen 9 5900XT (16 cores), 48 GB RAM, Windows 11 |
| Browser | Chromium 152.0.7977.167 (Electron 44, Claude desktop browser pane; pane hidden during runs) |
| Build | `flutter build web --release`, served locally by `tools/serve_web.py` (COOP/COEP, `no-store`) |
| Engine on web | `audio/web`: bare wasm (`cdylib`, plain C exports, no wasm-bindgen), built without `decode`/`output`, 325 KiB (724 KiB with `simd128`). Browser decodes MP3s (`decodeAudioData`) and transfers PCM to the worklet; Dart only posts events. |
| Before | Same build with `?audio=webaudio` (the D22 graph, unchanged) |
| Probes | `?mixprobe`: `epMeasureMix()` renders the Ode to Joy parity fixture (`audio/tests/fixtures/ode_to_joy_events.csv`) in an `OfflineAudioContext` at 44.1 kHz; `epMeasureLatency()` presses C4 and times `noteOn` → a tap worklet on the synth output reports the first audible sample (one message hop back included, same for both) |

Low-end device: not measured. The gates already fail on a fast desktop, so a slower device would not change the outcome.

## Results

| Gate | Web Audio (before) | Worklet engine (after) | Pass |
|---|---|---|---|
| Parity: part balance vs `ode_to_joy_web_levels.csv` | reference | BASS −4.11, DRUMS −7.36, PAD −14.06, CHOIR −13.19 dB vs ACC (reference −5.19, −8.22, −15.02, −13.99): worst 1.08 dB | yes (≤ 2 dB) |
| Parity: same output as native | n/a | mix −18.96 dBFS RMS, −0.82 peak; native `cargo test` gives the same −18.96 / −0.82 | yes |
| Audio-thread CPU: offline render of the 24 s song, all parts (7 renders each) | 1.5–2.2 s, mix 2.0 s | 4.1–8.0 s, mix 4.3 s (6.2 s with `simd128`) | **no** (about 2–3× the work) |
| Key latency: `noteOn` → first audible sample seen by the tap, 10 presses | median 6.4 ms, p90 10.4 ms | median 9.1 ms, p90 23.2 ms | **no** |
| First load: piano + click samples ready (`loadMs`, page reload, 4 runs) | 1651, 1682, 1765, 1772 ms | 1928, 2012, 2236, 2331 ms | **no** (≈ +20–30%: wasm fetch, worklet module, PCM transfer) |

Device output latency was the same for both (`baseLatency` 10 ms, `outputLatency` 32–40 ms at 48 kHz).

Notes:

- Latency: the worklet adds one message hop (main thread → audio thread) before the engine sees the key; Web Audio schedules `start(currentTime)` directly. The p90 spread is larger because a key that arrives just after a render quantum waits for the next.
- CPU: the engine does all voices, the FFT convolution reverb, two compressors and the soft clip per frame in scalar wasm; Web Audio does the same in native, vectorised nodes. The "piano solo" render (every part muted) costs as much as the full mix, so the cost is the per-frame chain, not voice count. SIMD for `rustfft` did not help.
- Memory is the one clear win (16-bit trimmed samples in the engine vs float32 AudioBuffers), but it is not a gate.

## Implications

- Stage 3 does not ship: web keeps the D22 Web Audio graph (`app/lib/audio/piano_synth_web.dart`), and stays matched to native through the stage-1 CI parity test (D30 fallback).
- The engine is correct on web (same output as native), so a later attempt only needs speed, not sound work.

## Follow-ups

- Bean: make the engine render cheaper per frame (block-based compressors and reverb instead of per-sample, skip silent buses), then rerun these gates from the spike branch.
- A blind A/B listen on web is not needed while web stays on Web Audio.
