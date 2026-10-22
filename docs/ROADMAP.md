# Roadmap

Don't start a phase until the user approves it. Tick boxes in the PR that delivers them.

## Phase 0: Decide and spike

- [x] User confirms D1–D9 (OQ1 name, OQ2 license still open)
- [x] Spike: Flutter web, Web MIDI/touch → colored key, first-load size ~2.5 MB gz ([results](research/web-midi-spike.md))
- [x] Measure Web MIDI p95 latency with a real keyboard (p95 8.1 ms, n=200, Keystation)
- [x] Spike: flutter_rust_bridge wasm on web (D2), Rust core in browser ([results](research/web-midi-spike.md))
- [ ] Android/iOS build smoke test (Android done, CI job `android`; iOS open)
- [x] Spike: staff rendering with Bravura, smooth scroll ([results](research/staff-render-spike.md))
- [ ] Research: Simply Piano numeric stats (stage mix, note ranges, bpm per course)
- [ ] Research: scene briefs for Piano Basics 1 reference videos via `agy`

## Phase 1: First playable

- [x] Monorepo scaffold, CI (Flutter, Rust, content lint)
- [x] Notation parser + JSON schemas + `content lint`
- [x] Core session: wait + play_along, critical sections, stars
- [x] Play-along error feedback and training mode (section replay, 75% practice runs)
- [x] Practice studio: staff + keyboard with hit/miss colors, fingering, key hints, results (`app/lib/practice/`)
- [ ] Falling notes view
- [x] Web only: Web MIDI + touch input; sampled piano synth (Web Audio), sound toggle, pre-listen, play-along companion + metronome
- [x] Deploy web build (static host with COOP/COEP headers): Cloudflare Pages, D15
- [x] 5 Piano Basics levels authored and lint-clean (`content/`)
- [ ] 5 Piano Basics 1 levels playable end to end

## Phase 2: Scenes and course map

- [ ] Scene player (keyboard, hands, staff, captions)
- [ ] Journey map UI, progress store, star gates
- [ ] Piano Basics 1 complete (~25 levels, 10 scenes, 5 PD songs)
- [ ] Android + iOS builds with native MIDI; desktop stretch

## Phase 3: Mic and library

- [x] Mic detection (single notes + chords) + calibration, web ([input](specs/input.md), [research](research/mic-input.md)); native capture pending
- [ ] MusicXML/MIDI importers; song library with 30 PD pieces
- [ ] Daily workout, streaks, daily goal

## Phase 4: Content scale

- [x] Essentials I (19 levels, 2 star gates)
- [x] Essentials II (18 levels, 2 star gates)
- [x] Essentials III (17 levels, 2 star gates)
- [ ] Piano Basics 2–4, Pop Chords 1
- [x] Localization: en, pt-BR, es, fr, de UI and content strings, language picker ([i18n](specs/i18n.md))
- [ ] Polyphonic mic research result
- [x] Endless practice on web: generated music streamed while you play, level and rules picked by the learner, rubric-gated, labelled, no stars (D28, [spec](specs/practice-mode.md))
- [ ] Practice mode on Android/iOS/desktop (native ONNX runtime)
- [x] Publish the `melody-model-v1` release; deploy serves its files same-origin

## Phase 5: My songs (D11)

- [ ] Import own audio/MIDI/MusicXML, on-device stem separation + transcription
- [ ] Play along with backing stems (mute vocals / piano)
- [ ] Level-based arranger in core (beginner / intermediate / advanced)

## Later

Sync, teacher tools, more tracks, store releases.
