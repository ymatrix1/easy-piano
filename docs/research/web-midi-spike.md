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
| Web MIDI → frame start | 0 | n/a | n/a | **Not measured: no MIDI keyboard attached** |

Functional check: keys render C3–C6, touch press/release correct per pointer (stuck-key bug found and fixed), `flutter analyze` clean, 4 unit tests pass (`app/test/widget_test.dart`).

## Not done

- Web MIDI latency with a real keyboard (needs user's device). The app shows p50/p95 live after "Connect MIDI".
- flutter_rust_bridge wasm path (D2). Spike used pure Dart.
- Android/iOS build smoke test (needs Android SDK / macOS).

## Implications

- Flutter web passes the load-size gate; D1 + D9 stand.
- `MIDIMessageEvent.timeStamp` shares the `performance.now()` clock, so input→frame latency is directly measurable in-app.
- Host must serve `.wasm` with gzip/brotli; Content plan should budget ~2.5 MB engine + content packs.

## Follow-ups

- Measure Web MIDI p95 with a USB keyboard on Chrome (user run).
- Bean: flutter_rust_bridge wasm spike.
