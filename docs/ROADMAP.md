# Roadmap

Don't start a phase until the user approves it. Tick boxes in the PR that delivers them.

## Phase 0: Decide and spike

- [ ] User confirms D1–D8 and OQ1–OQ2
- [ ] Spike: Flutter web + flutter_rust_bridge wasm; Web MIDI in → colored key; measure latency and first-load size (OQ7). Android/iOS build smoke test only
- [ ] Spike: staff rendering with Bravura, 60 fps scroll
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

## Later

Sync, teacher tools, more tracks, store releases.
