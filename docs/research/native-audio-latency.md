# Native audio output latency (Windows)

Checked: 2026-10-20. Bean: piano-73n9 (context). Setup: Windows 11 Pro, 48 kHz, five active output devices (USB audio, three NVIDIA HDMI endpoints, Steam Streaming Speakers, Voicemod virtual), Rust 1.91. Browser: Chrome 152 inside the Claude desktop pane. Probe code was throwaway (not committed): `cpal` 0.15 for shared mode, `windows` 0.58 crate for IAudioClient / IAudioClient3 and exclusive mode. Output was silence; only buffer timing was measured.

Sources: [WASAPI exclusive mode](https://learn.microsoft.com/windows/win32/coreaudio/exclusive-mode-streams), [IAudioClient3](https://learn.microsoft.com/windows/win32/api/audioclient/nn-audioclient-iaudioclient3), `cpal` and `miniaudio` project docs.

## Question

How much audio output latency can a native build save over the web build, and which approach gets it?

## Results

Callback timing is measured per path. These are buffer periods, not end-to-end key-to-sound latency, which needs a hardware loopback.

| Path | Buffer period | Callback gap p95 / max | Notes |
|---|---|---|---|
| Browser Web Audio, `latencyHint` `'interactive'` | `baseLatency` 10 ms | n/a | `outputLatency` 40 ms |
| Browser Web Audio, `latencyHint` 0 | `baseLatency` 10 ms | n/a | Identical to `'interactive'` (5 runs each) |
| `cpal` WASAPI shared, requested 64 / 128 / 256 / 480 frames | 480 frames = 10 ms | 10.1 / 10.6 ms | Requested size ignored; 10 ms is the system period |
| WASAPI shared via IAudioClient3 | min period 10 ms on all 5 devices | not streamed | These drivers expose no smaller shared period |
| WASAPI exclusive, USB audio | 144 frames = 3.00 ms | 3.02 / 6.16 ms | 1000 callbacks, one 6 ms outlier |
| WASAPI exclusive, HDMI monitor audio | 160 frames = 3.33 ms | 3.34 / 3.46 ms | 901 callbacks |

Exclusive-mode format support (all five devices): PCM16 at 48 kHz supported. Float (the shared mix format) and PCM24 are rejected on most. Min exclusive period reported by the driver: 3 ms on all five.

## Not measured

- `miniaudio`: Rust bindings need libclang, not installed. Same WASAPI exclusive backend underneath; numbers expected to match, not verified.
- `flutter_soloud` (SoLoud): needs the Flutter app running plus a loopback test.
- Oboe (Android), CoreAudio (iOS/macOS): need those devices.
- End-to-end key to sound, MIDI p95 on the web build: needs a physical keyboard.

## Implications

- `cpal` in shared mode gains nothing over the browser's 10 ms `baseLatency`.
- WASAPI exclusive cuts the buffer about 3x (10 ms to 3 ms) on this machine. Browser `outputLatency` was 40 ms, so the total saving is likely larger than the buffer alone; unmeasured.
- A native sampler must output PCM16 in exclusive mode (or convert) and fall back to shared mode when exclusive is unavailable or the device is in use.
- Web builds keep the browser's limit. `latencyHint` tuning does nothing here.

## Follow-ups

- Run the MIDI latency spike on the PR preview with a keyboard and record web p95 (compare D1's 30 ms gate).
- Loopback test (output to input) to get true end-to-end numbers.
- Install libclang and measure `miniaudio` exclusive; try `flutter_soloud` in the app.
- Measure Oboe on one Android phone and CoreAudio on one Apple device before choosing per-platform backends.
