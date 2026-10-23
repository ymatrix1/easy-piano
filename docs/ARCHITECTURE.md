# Architecture

Status: accepted ([D1](DECISIONS.md), [D2](DECISIONS.md)). Nothing built yet.

## Overview

```
┌──────────────────────────── Flutter app (Dart) ────────────────────────────┐
│ App shell: map, library, profile, settings (widgets)                       │
│ Practice studio: staff / falling-notes / keyboard (CustomPainter + Ticker) │
│ Scene player: animation stages (CustomPainter, same renderer)              │
│ Content loader + validator, progress store (SQLite/drift)                  │
└───────────────▲────────────────────────────────────────────▲───────────────┘
                │ flutter_rust_bridge (FFI native / wasm web)  │
┌───────────────┴──────────── core (Rust crate) ──────────────┴───────────────┐
│ notation: parse note text → Score        grading: matcher, critical sections│
│ clock: audio-hardware master clock       session: wait / play-along state   │
│ synth: soundfont playback                input: MIDI events, mic → notes    │
└──────────────────────────────────────────────────────────────────────────────┘
  Platform I/O: CoreMIDI/CoreAudio · android.media.midi/Oboe · Web MIDI/AudioWorklet · WinMM/WASAPI/ALSA
```

## Packages (planned monorepo)

| Path | Lang | Role |
|---|---|---|
| `app/` | Dart/Flutter | UI, navigation, rendering, persistence |
| `core/` | Rust | Pure logic: notation, grading, session state machine. No I/O. 100% unit-tested |
| `audio/` | Rust | One engine for every platform ([D30](DECISIONS.md)): sampler, mix and effects with a CI parity test vs web (stage 1); native output via cpal (WASAPI/CoreAudio/AAudio) behind `PianoSynth` on Android, iOS and desktop (stage 2); web AudioWorklet, mic capture and pitch detection to come |
| `content/` | JSON + text | Courses, journeys, levels, songs, scenes, strings |
| `tools/content-cli/` | Rust | `lint`, `preview`, `import-midi`, `import-musicxml`, `stats` |
| `docs/` | Markdown | This planning set |

## Key flows

**Key press (MIDI):** platform MIDI callback → Dart plugin (or Web MIDI) → `core.on_note(pitch, vel, t_audio)` → grader updates → next frame reads `poll_frame()` → paint hit/miss. Target ≤ 30 ms.

MIDI input stays on the platform side (Dart plugin per OS) rather than in Rust `midir`, because `midir` lacks Android/iOS BLE and web. Events are timestamped against the audio clock before entering core. See [input spec](specs/input.md).

**Clock:** the audio output stream is the master clock. UI never advances song time from frame deltas. Play-along position = `audio_time - start - latency_offset`.

**Content:** app ships Piano Basics 1 in bundle; other courses download as versioned zip packs with SHA-256 manifest; cached offline.

## Rendering

- Staff: SMuFL glyphs from Bravura font via `TextPainter`; layout precomputed per level; visible-window culling.
- Falling notes and keyboard share one `KeyGeometry` helper so lanes align with keys.
- Scenes (video replacement) reuse the same painters plus a hand-model layer. See [animations](specs/animations.md).

## Data

Local SQLite: profile, per-level best score, stars, attempts, streak, settings, device latency offset. Optional sync later ([OQ5](OPEN-QUESTIONS.md)); local-first default.

## Deploy (web)

[D15](DECISIONS.md) (proposed). `.github/workflows/deploy-web.yml` builds on GitHub Actions (`tools/sync_content.py` → `flutter_rust_bridge_codegen build-web --release` → `flutter build web --release`) and uploads `app/build/web` to Cloudflare Pages project `easy-piano`: production on push to `main`, a preview per PR (URL in a PR comment). `app/web/_headers` sets COOP/COEP/CORP and asset caching. Secrets: `CLOUDFLARE_API_TOKEN` (Pages edit), `CLOUDFLARE_ACCOUNT_ID`. `.github/workflows/release.yml` builds the web app, Windows x64 bundle, and Android arm64 APK from `vMAJOR.MINOR.PATCH` tags, then attaches versioned assets to GitHub Releases with generated notes. The Android APK is debug-signed for sideloading; it is not a Play Store package. Release builds do not deploy the tagged web build to Pages.

## Build (Android)

Phones are `arm64-v8a`. Build the installable APK with:

```
python tools/sync_content.py
cd app && flutter build apk --release --target-platform android-arm64
```

Output: `app/build/app/outputs/flutter-apk/app-release.apk` (debug-signed for now). Don't sideload an APK from `flutter run` on an emulator: it carries only the emulator's ABI (`x86_64`) and crashes on a phone with `Could not find 'libflutter.so'`.

Native-library notes:

- cpal reaches AAudio through Oboe (C++). `app/rust/build.rs` links the NDK's `c++_static` + `c++abi`; without them the bridge fails to load (`cannot locate symbol "__cxa_pure_virtual"`).
- cpal reads the JavaVM and Context from `ndk-context`. `MainActivity` loads `libeasy_piano_bridge.so` and calls `initAndroidContext` (`app/rust/src/android.rs`) before Flutter starts.
- Launcher icon, label and splash (brand `#15104F` + logo) live in `app/android/app/src/main/res` and the manifest.

CI (`ci.yml`, job `android`) builds the arm64 APK, checks its native libraries, uploads it as artifact `easy-piano-arm64-apk`, and boots the app to the home screen on an API 34 x86_64 emulator (`integration_test/app_smoke_test.dart`). Cargo (cargokit target dir), Gradle, Flutter/pub and the AVD snapshot are cached.

## Build (Windows)

Build the x64 desktop app on Windows with Flutter, Rust's `x86_64-pc-windows-msvc` target, and Visual Studio 2022's **Desktop development with C++** workload:

```powershell
rustup target add x86_64-pc-windows-msvc
python tools/sync_content.py
cd app
flutter pub get
flutter build windows --release
```

Flutter writes the runnable bundle to `app/build/windows/x64/runner/Release/`. Distribute the entire directory together; the `.exe` alone is not sufficient. Users need Windows 10 or later (64-bit) and the [Microsoft Visual C++ v14 Redistributable for x64](https://aka.ms/vc14/vc_redist.x64.exe). The portable ZIP includes a short run guide and does not install an updater or Start menu shortcut.

CI (`.github/workflows/windows-release.yml`) builds this bundle on pull requests, pushes to `main`, and manual runs. It uploads `easy-piano-windows-x64.zip` as a 14-day workflow artifact. Pushing a version tag such as `v1.2.3` also creates a GitHub Release with autogenerated notes and the ZIP attached. The build caches Flutter packages and the Cargokit Rust output.

This pipeline verifies packaging and compilation. Windows MIDI and microphone input, installer signing, and in-place updates are outside this delivery.

## Platform matrix

| Target | MIDI | Mic | Notes |
|---|---|---|---|
| Android | `android.media.midi` (USB + BLE) via channel | `AudioRecord` via channel, Dart detector ([D36](DECISIONS.md)) | min SDK 26 |
| iOS/iPadOS | CoreMIDI (USB + BLE) | AVAudioEngine | |
| Web (Chrome/Edge/Firefox) | Web MIDI | AudioWorklet | COOP/COEP headers for wasm threads |
| Web Safari | none → mic/touch | AudioWorklet | banner |
| Desktop (Win/macOS/Linux) | native | native | stretch goal, nearly free with Flutter |
