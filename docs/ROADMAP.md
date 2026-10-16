# Roadmap

Don't start a phase until the user approves it. Tick boxes in the PR that delivers them.

## Phase 0: Decide and spike

- [x] User confirms D1–D9 (OQ1 name, OQ2 license still open)
- [x] Spike: Flutter web, Web MIDI/touch → colored key, first-load size ~2.5 MB gz ([results](research/web-midi-spike.md))
- [x] Measure Web MIDI p95 latency with a real keyboard (p95 8.1 ms, n=200, Keystation)
- [x] Spike: flutter_rust_bridge wasm on web (D2), Rust core in browser ([results](research/web-midi-spike.md))
- [ ] Android/iOS build smoke test
- [x] Spike: staff rendering with Bravura, smooth scroll ([results](research/staff-render-spike.md))
- [ ] Research: Simply Piano numeric stats (stage mix, note ranges, bpm per course)
- [ ] Research: scene briefs for Piano Basics 1 reference videos via `agy`

## Phase 1: First playable

- [ ] Monorepo scaffold, CI (Flutter, Rust, content lint)
- [ ] Notation parser + JSON schemas + `content lint`
- [ ] Core session: wait + play_along, critical sections, stars
- [ ] Practice studio: staff + keyboard, falling notes view
- [ ] Web only: Web MIDI + touch input; soundfont synth (AudioWorklet)
- [ ] Deploy web build (static host with COOP/COEP headers)
- [ ] 5 Piano Basics 1 levels playable end to end

## Phase 2: Scenes and course map

- [ ] Scene player (keyboard, hands, staff, captions)
- [ ] Journey map UI, progress store, star gates
- [ ] Piano Basics 1 complete (~25 levels, 10 scenes, 5 PD songs)
- [ ] Android + iOS builds with native MIDI; desktop stretch

## Phase 3: Mic and library

- [ ] Mic monophonic detection + calibration
- [ ] MusicXML/MIDI importers; song library with 30 PD pieces
- [ ] Daily workout, streaks, daily goal

## Phase 4: Content scale

- [ ] Piano Basics 2–4, Essentials 1, Pop Chords 1
- [ ] Localization (pt-BR, es)
- [ ] Polyphonic mic research result

## Phase 5: My songs (D11)

- [ ] Import own audio/MIDI/MusicXML, on-device stem separation + transcription
- [ ] Play along with backing stems (mute vocals / piano)
- [ ] Level-based arranger in core (beginner / intermediate / advanced)

## Later

Sync, teacher tools, more tracks, store releases.
