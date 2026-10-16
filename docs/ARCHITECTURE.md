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
| `audio/` | Rust | Audio out (cpal/oboe), synth, mic capture, pitch detection |
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

[D13](DECISIONS.md) (proposed). `.github/workflows/deploy-web.yml` builds on GitHub Actions (`tools/sync_content.py` → `flutter_rust_bridge_codegen build-web --release` → `flutter build web --release`) and uploads `app/build/web` to Cloudflare Pages project `easy-piano`: production on push to `main`, a preview per PR (URL in a PR comment). `app/web/_headers` sets COOP/COEP/CORP and asset caching. Secrets: `CLOUDFLARE_API_TOKEN` (Pages edit), `CLOUDFLARE_ACCOUNT_ID`.

## Platform matrix

| Target | MIDI | Mic | Notes |
|---|---|---|---|
| Android | `android.media.midi` (USB + BLE) | Oboe | min SDK 26 |
| iOS/iPadOS | CoreMIDI (USB + BLE) | AVAudioEngine | |
| Web (Chrome/Edge/Firefox) | Web MIDI | AudioWorklet | COOP/COEP headers for wasm threads |
| Web Safari | none → mic/touch | AudioWorklet | banner |
| Desktop (Win/macOS/Linux) | native | native | stretch goal, nearly free with Flutter |
