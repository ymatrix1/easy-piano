# Open questions

| # | Question | Notes |
|---|---|---|
| OQ1 | Final project name? | Working name Easy Piano (repo). Candidates: Fermata (wait-mode pun), Tasto, Klavia. Check GitHub/stores/trademark collisions |
| OQ2 | Code license: MPL-2.0, GPL-3.0 or Apache-2.0? | GPL blocks closed forks but complicates App Store; MPL is a middle ground |
| OQ3 | Piano samples: which open soundfont, and size budget for bundle vs download? | Salamander Grand (CC-BY) is ~300 MB raw; need a compressed 10–20 MB cut |
| OQ4 | Hand model in scenes: 2D vector hands drawn in code, or Rive asset? | 2D code-driven is data-aware; Rive looks better. Spike in Phase 2 |
| OQ5 | Sync: none, self-hostable server, or file export/import? | D8 says local-first |
| OQ6 | Voice-over in scenes: none, TTS at build time, or recorded? | TTS keeps localization cheap |
| OQ7 | Does Flutter Web + flutter_rust_bridge wasm meet the latency budget? | Phase 0 spike answers |
| OQ9 | How do we detect a learner's current level (placement) and choose their start node? | Until answered every course and node stays open; star gates score progress but never lock. Draft: [specs/placement.md](specs/placement.md). Bean piano-vg8h |
| OQ8 | How far do we mirror Simply Piano's course list vs design our own order? | Proposal in [curriculum](specs/curriculum.md) |
| OQ12 | How are expression marks graded: dynamics by MIDI velocity bands, staccato by held length, pedal by MIDI CC64, and what does mic input do with them? | Method books teach them from unit 1; notation has none. [gap table](research/method-books-sequence.md), beans piano-boat (expression) and piano-h90n (ties, repeats, key/meter changes) |
| OQ13 | Are Piano Basics 2–4 still wanted, or do Essentials I–III replace them? | curriculum.md lists PB1–4; course-map and the built path use Piano Basics → Essentials I–III |
| OQ11 | Accept mic timing logic in Dart instead of Rust `core` (rule 7)? | [D29](DECISIONS.md): onset/chord detection, calibration median and the MIDI/mic echo window run in Dart on web (AudioWorklet → Dart, no per-chunk FFI). Grading stays in `core`. Options: accept for web, or port `NoteDetector` to `core` with the native audio thread. [D32](DECISIONS.md) adds a trained note model that decodes in a JS Web Worker, so the deviation grows: pick one place for mic detection (web JS/Dart, or a Rust `core`/`audio` model runtime with the native audio thread). D29 and D32 stay proposed until answered |
