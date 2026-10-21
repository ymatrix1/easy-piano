# Web MIDI spike

Checked: 2026-10-15. Bean: piano-l3rl. Setup: Flutter 3.47.7 (Dart 3.13.5), `flutter build web --release` (CanvasKit), served by `python -m http.server`, Claude desktop browser pane (Chromium), Windows 11. Code: `app/lib/input/`, `app/lib/ui/`, `app/lib/main.dart`.

## Question

Does Flutter web meet D9's gates: first load ≤ 5 MB and MIDI → frame ≤ 30 ms p95?

## Results

**First load (Chromium path), gzip -9:**

| File | Raw | Gzip |
|---|---|---|
| main.dart.js | 1.82 MB | 0.53 MB |
| canvaskit/chromium/canvaskit.wasm | 5.18 MB | 1.96 MB |
| canvaskit.js + bootstrap | 0.09 MB | 0.03 MB |
| **Total** | **7.09 MB** | **~2.5 MB** |

`build/web` is 40 MB on disk because it holds every renderer variant; a browser downloads one. Non-Chromium browsers fetch the generic `canvaskit.wasm` (2.78 MB gz), for ~3.3 MB total. Both pass the 5 MB gate.

**Latency:**

| Path | n | p50 | p95 | Notes |
|---|---|---|---|---|
| Touch (mouse click) → frame start | 3 | 2.5 ms | 2.9 ms | Timestamp taken in Dart handler; excludes browser input dispatch. Lower bound only |
| Web MIDI → frame start (M-Audio Keystation Mini 32, USB, Chrome, 2026-10-16) | 200 | 3.5 ms | 8.1 ms | max 10.6 ms. Passes 30 ms gate (first run n=11: p50 5.8, p95 7.4) |

Functional check: keys render C3–C6, touch press/release correct per pointer (stuck-key bug found and fixed), `flutter analyze` clean, 4 unit tests pass (`app/test/widget_test.dart`).

## flutter_rust_bridge on web (bean piano-hyle, 2026-10-16)

Setup: flutter_rust_bridge 2.13.0, wasm-pack 0.15.0, Rust nightly + rust-src (atomics build). Bridge crate `app/rust` (`easy_piano_bridge`) wraps pure crate `core/` (`easy_piano_core`); API in `app/rust/src/api/notation.rs`.

| Check | Result |
|---|---|
| `cargo test` in `core/` | 5 passed |
| `flutter_rust_bridge_codegen build-web --release` | ok, 40 s |
| Rust wasm size | `easy_piano_bridge_bg.wasm` 92 KB raw + 29 KB JS glue |
| Browser (Chromium, `tools/serve_web.py` with COOP/COEP) | `crossOriginIsolated: true`; page shows `C4 = 60` from Rust; tapped keys named by Rust (`D#3`); no console errors |
| Sync FRB call per key press | input→frame sample 4.1 ms (n=1, lower bound as above) |

Gotchas: `integrate` comments out the existing `main.dart` and adds a demo; restore it. Web needs COOP/COEP headers (dev: `tools/serve_web.py`; prod host must set them). Build order for web: `flutter_rust_bridge_codegen build-web --release` then `flutter build web --release`.

## Not done

- iOS build smoke test (needs macOS).

## Android smoke test (2026-10-21)

| Check | Result |
|---|---|
| Samsung Galaxy S23 Ultra (SDK release 16), release APK `--target-platform android-arm64` | boots to home screen; nothing in `logcat -b crash` |
| Sideloaded APK built for the emulator | crash: `Could not find 'libflutter.so'... only found: [x86_64]` |
| First arm64 APK | `RustLib.init` failed: `cannot locate symbol "__cxa_pure_virtual"` (Oboe C++ runtime not linked); fixed in `app/rust/build.rs` |
| CI emulator, API 34 x86_64 | `integration_test/app_smoke_test.dart` must reach `HomePage` (job `android`) |

## Implications

- Flutter web passes the load-size gate; D1 + D9 stand.
- Rust core runs on web through FRB at small cost (~0.1 MB); D2 stands.
- `MIDIMessageEvent.timeStamp` shares the `performance.now()` clock, so input→frame latency is directly measurable in-app.
- Host must serve `.wasm` with gzip/brotli; Content plan should budget ~2.5 MB engine + content packs.

## Follow-ups

- Measure Web MIDI p95 with a USB keyboard on Chrome (user run).

## Yamaha "Digital Piano" sends nothing (2026-10-16)

USB device `VID_0499&PID_160F` enumerates as "Digital Piano" and Chrome/rtmidi can open it, but it delivered **0 messages** in 20 s windows, both in Chrome and via native `python-rtmidi`, after replug and power cycle. Keystation on the same machine works, so the cause is that piano, its cable/port, or Windows MIDI Services (`MidiSrv`), not the app. Unresolved.
